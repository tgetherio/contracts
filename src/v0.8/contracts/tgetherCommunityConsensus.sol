// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";

import "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";

interface tgetherCommuunitiesInterfact{
    function getCommunityOwner(string memory _communityName) external view returns (address);
    function CustomProposal(string memory _communityName,address _contractAddress)external payable returns(uint256);
    function getProposalResults( uint256 _proposalId ) external view returns (bool isActive, bool passed );
    function getFee() external view returns(uint256);
}

interface tgetherFundInterface{
        function fundUpkeep(address _contractAddress) external payable returns (bool);
    }


contract tgetherCommunityConsensus is ILogAutomation{
    // CC= ComunityConsensus

    struct CCParams{
        uint256 numReviewsForAcceptance; // number of reviews needed for acceptance
        uint256 credsNeededForReview; // number of creds needed for a review to count
        uint256 percentAcceptsNeeded; // percentage of accepts needed for acceptance
        uint256 consensusTime; // time in seconds for the consensus to be active
        string[] consensusTypes; // extra types of consensus to provide reason for not accepted (can be empty)
        bool isSet; // if true the community has been created
    }

    struct CCProposalParams{
        address proposer;
        string communityName;
        uint256 numReviewsForAcceptance;
        uint256 credsNeededForReview;
        uint256 percentAcceptsNeeded;
        uint256 consensusTime;
        bool upkeeped;
        bool passed;
        string[] consensusTypes;
    }

    mapping(string => CCParams) public communityConsensus;
    mapping(uint256 => CCProposalParams) public CommunityConsensusProposals;
    mapping(string => uint256[]) public ConsensusProposalArray;


    address private owner;
    uint256 public fee;
    uint256 public maxConsensusTime;
    uint256 public communityFee;
    uint256 public totalFee;
    tgetherFundInterface public FundContract;


    tgetherCommuunitiesInterfact public CommunityContract;
    address thisAddress = address(this);

    uint256 public upkeepId;
    constructor(uint256 _feePrice, address _communityContractAddress, uint256 _communityFee, address _fundContract) {
        owner = msg.sender;

        CommunityContract= tgetherCommuunitiesInterfact(_communityContractAddress);
        FundContract = tgetherFundInterface(_fundContract);

        fee = _feePrice;
        communityFee = _communityFee;
        totalFee = fee + communityFee;

        // Array Time Dependent variables set to 3 months by default can be changed by setters
        maxConsensusTime = 7890000;
    }


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }


    // Events 
    

    event CCProposalCreated(uint256 indexed proposalId, address proposer, uint256 numReviewsForAcceptance, uint256 credsNeededForReview, uint256 percentAcceptsNeeded, uint256 consensusTime, string[] consensusTypes);
    event CCParamCreated(string indexed communityName, uint256 numReviewsForAcceptance, uint256 credsNeededForReview, uint256 percentAcceptsNeeded, uint256 consensusTime, string[] consensusTypes);
        


    // Functions



    /*

        * @notice Allows a community owner to set initial values if not already set
        * @dev Ensures the caller owner of the community.
        * @param _communityName Name of the community to set the conseous for.
        * @param _numReviewsForAcceptance Number of reviews needed for acceptance.
        * @param _credsNeededForReview Number of creds needed for a review to count.
        * @param _percentAcceptsNeeded Percentage of accepts needed for acceptance.
        * @param _consensusTime Time in seconds for the consensus to be active.
        * @param _consensusTypes Extra types of consensus to provide reason for not accepted (can be empty).
        * @return bool if the conseous was set.

    */
   function setCCParams(     
        string memory _communityName,   
        uint256 _numReviewsForAcceptance,
        uint256 _credsNeededForReview,
        uint256 _percentAcceptsNeeded,
        uint256 _consensusTime,
        string[] memory _consensusTypes
        ) external returns(bool){
            require(CommunityContract.getCommunityOwner(_communityName) == msg.sender, "User is not the owner of this community");
            require( communityConsensus[_communityName].isSet == false, "Community Consensus Parameters already set");

            if(_consensusTime > maxConsensusTime) {
                _consensusTime = maxConsensusTime;
            }

            CCParams storage ccP = communityConsensus[_communityName];

            ccP.numReviewsForAcceptance = _numReviewsForAcceptance;
            ccP.credsNeededForReview = _credsNeededForReview;
            ccP.percentAcceptsNeeded = _percentAcceptsNeeded;
            ccP.consensusTime= _consensusTime;
            ccP.consensusTypes = _consensusTypes;
            ccP.isSet = true;
            return ccP.isSet;
        }



    /*
        * @notice Allows a member to create a proposal for a community conseous.
        * @dev Handles all member logic and creates a proposal on the community contract.
        * @param _communityName Name of the community to set the conseous for.
        * @param _numReviewsForAcceptance Number of reviews needed for acceptance.
        * @param _credsNeededForReview Number of creds needed for a review to count.
        * @param _percentAcceptsNeeded Percentage of accepts needed for acceptance.
        * @param _consensusTime Time in seconds for the consensus to be active.
        * @param _consensusTypes Extra types of consensus to provide reason for not accepted (can be empty).
        * @return uint256 ID of the proposal.
    */

    // Fee is sent to this contract and then sent to the community contract, also collected by the owner of this contract


    /**
    * DISCLAIMER:
    * By signing and submitting this transaction, you acknowledge that you are contributing funds to a shared pool 
    * rather than directly funding your individual upkeep execution. This pooling mechanism is designed to optimize 
    * resource allocation and minimize transaction costs.
    *
    * Please be aware that price volatility may affect the availability of funds required to process your upkeep. 
    * In such cases, your upkeep may not be automatically executed. However, you retain the option to manually 
    * execute your upkeep at any time by calling the performUpkeep function.
    *
    * Ensure you understand the risks associated with price fluctuations and the potential impact on the automatic 
    * processing of your upkeep.
    */

    function CreateCCProposal(
        string memory _communityName,   
        uint256 _numReviewsForAcceptance,
        uint256 _credsNeededForReview,
        uint256 _percentAcceptsNeeded,
        uint256 _consensusTime,
        string[] memory _consensusTypes
    )external payable returns(uint256){

        require(msg.value == totalFee, "Fee price not sent");


        uint256 proposalId = CommunityContract.CustomProposal{value: communityFee}(_communityName, address(this));
        require(proposalId > 0, "Proposal not created");

        if(_consensusTime > maxConsensusTime) {
                _consensusTime = maxConsensusTime;
            }
        CCProposalParams memory ccPP = CommunityConsensusProposals[proposalId];
        ccPP.proposer = msg.sender;
        ccPP.communityName = _communityName;
        ccPP.numReviewsForAcceptance = _numReviewsForAcceptance;
        ccPP.credsNeededForReview = _credsNeededForReview;
        ccPP.percentAcceptsNeeded = _percentAcceptsNeeded;
        ccPP.consensusTime= _consensusTime;
        ccPP.consensusTypes = _consensusTypes;
        emit CCProposalCreated(proposalId, msg.sender, _numReviewsForAcceptance, _credsNeededForReview, _percentAcceptsNeeded, _consensusTime, _consensusTypes);
        
        bool _isFunded = FundContract.fundUpkeep{value: msg.value - communityFee}(address(this));
        if (_isFunded) {
            CommunityConsensusProposals[proposalId] = ccPP;
            ConsensusProposalArray[_communityName].push(proposalId);
        } else {
            revert();
        }

        return proposalId;
    }



    /*
        * @notice Checklog function for the upkeep of the contract.
        * @dev Ensures the proposal exists in this contract and is not upkeeped.
        * @param log The log to check.
        * @return _performData The bytes transformed proposal id to upkeep
        * @return upkeepNeeded If the upkeep is needed.
    */

    function checkLog(
        Log calldata log,
        bytes memory 
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        address _contractAddress = bytes32ToAddress(log.topics[1]);
        uint256 _proposalId = uint256(log.topics[2]);

        if(_contractAddress == thisAddress && CommunityConsensusProposals[_proposalId].proposer != address(0) && CommunityConsensusProposals[_proposalId].upkeeped == false ){
            upkeepNeeded = true;
            
        }
        
        return (upkeepNeeded, abi.encode(_proposalId));


    }

    /*

        * @notice Performs the upkeep of the contract.
        * @dev Ensures the proposal exists in this contract and is not upkeeped.
        * @dev Ensures the proposal is no longer active and updates the community conseous if passed.
        * @param _performData The bytes transformed proposal id to upkeep
    */
    function performUpkeep(bytes calldata _performData) external  {

        uint256 _proposalId = abi.decode(_performData, (uint256));

        if(CommunityConsensusProposals[_proposalId].proposer != address(0)){
            (bool _isActive, bool _passed) = CommunityContract.getProposalResults(_proposalId);


            // We can use _isActive here because we already know the proposal exists, and when created is set to true
            if (_isActive == false){
                if (_passed){
                    CCProposalParams memory ccPP = CommunityConsensusProposals[_proposalId];
                    ccPP.upkeeped = true;
                    ccPP.passed = true;
                    CommunityConsensusProposals[_proposalId] = ccPP;
                    CCParams storage ccP = communityConsensus[ccPP.communityName];

                    ccP.numReviewsForAcceptance = ccPP.numReviewsForAcceptance;
                    ccP.credsNeededForReview = ccPP.credsNeededForReview;
                    ccP.percentAcceptsNeeded = ccPP.percentAcceptsNeeded;
                    ccP.consensusTime= ccPP.consensusTime;
                    ccP.consensusTypes = ccPP.consensusTypes;

                    if (ccP.isSet == false){
                        ccP.isSet = true;
                    }

                    emit CCParamCreated(ccPP.communityName, ccPP.numReviewsForAcceptance, ccPP.credsNeededForReview, ccPP.percentAcceptsNeeded, ccPP.consensusTime, ccPP.consensusTypes);
                }else{
                    CCProposalParams memory ccPP = CommunityConsensusProposals[_proposalId];
                    ccPP.upkeeped = true;
                    ccPP.passed = false;
                    CommunityConsensusProposals[_proposalId] = ccPP;
                }

            }
        }


    }



    // Helper Functions
    function bytes32ToAddress(bytes32 _address) public pure returns (address) {
        return address(uint160(uint256(_address)));
    }


    function getCCParams(string memory _communityName) external view returns( uint256 _numReviewsForAcceptance, uint256 _credsNeededForReview, uint256 _percentAcceptsNeeded, uint256 _consensusTime, string[] memory _consensusTypes, bool _isSet){
        return (communityConsensus[_communityName].numReviewsForAcceptance, communityConsensus[_communityName].credsNeededForReview, communityConsensus[_communityName].percentAcceptsNeeded, communityConsensus[_communityName].consensusTime, communityConsensus[_communityName].consensusTypes, communityConsensus[_communityName].isSet);
    }
    function getCCParamsExist(string memory _communityName) external view returns(bool _isSet){
        return (communityConsensus[_communityName].isSet);
    }

    function getCommunityConsensousTime(string memory _communityName) external view returns (uint256){
        return (communityConsensus[_communityName].consensusTime);
    }
    function getCommunityConsensousTypes (string memory _communityName) external view returns (string[] memory consensusTypes){
        return (communityConsensus[_communityName].consensusTypes);
    }
    function getCommunityReviewParams (string memory _communityName) external view returns (uint256 numReviewsForAcceptance,uint256 credsNeededForReview,uint256 percentAcceptsNeeded){
        return (communityConsensus[_communityName].numReviewsForAcceptance,communityConsensus[_communityName].credsNeededForReview,communityConsensus[_communityName].percentAcceptsNeeded);
    }
    function getConsensusProposalArray(string memory _communityName) external view returns (uint256[] memory){
        return ConsensusProposalArray[_communityName];
    }




    // Only Owner Funcitons

    function settgetherCommunityContract(address _contractAddress) external onlyOwner {
        CommunityContract= tgetherCommuunitiesInterfact(_contractAddress);

    }

    function setFee(uint256 _feePrice) external onlyOwner {
        fee= _feePrice;
    }


    function setMaxConsensusTime(uint256 _mrt) external onlyOwner {
       maxConsensusTime= _mrt;

    }
    function UpdateTotalFee() external onlyOwner {
        uint256 _comfee =CommunityContract.getFee();

        communityFee = _comfee;
        totalFee = fee + _comfee;
    }
    function setFundContract(address _contract) external onlyOwner {
       FundContract= tgetherFundInterface(_contract);

    }




}