// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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


contract tgetherIncentives is ILogAutomation{
    
    /**
     * Types of consensus strcutes for a community 
     * Equal - All members who review receive the same reward
     * consensusAligned - Members who review and are in consensus with the majority receive the reward
     */
    enum IncentiveStructure { Equal, consensusAligned } 


    struct IncentiveParams{
        IncentiveStructure structure;
        uint256 communityFee;
        address payable contractRecieveAddress;
        bool isSet;
    }

    struct IncentiveProposal{
        address proposer;
        string communityName;
        IncentiveStructure structure;
        uint256 communityFee;
        address payable contractRecieveAddress;
        bool upkeeped;
        bool passed;
    }

    mapping(string => IncentiveParams) public IncentiveStructures;
    mapping(uint256 => IncentiveProposal) public IncentiveProposals;

    string[] public ContractParameterKeys= ["structure", "communityFee", "contractRecieveAddress", "isSet"];
    
    address private owner;
    uint256 public fee;
    uint256 public TGcommunitiesFee;
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
        TGcommunitiesFee = _communityFee;
        totalFee = fee + TGcommunitiesFee;
    }


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }


    // Events 
    
    event IncentiveStructureSet( string communityName, IncentiveStructure structure, uint256 communityFee, address payable contractRecieveAddress);
    event IncentiveProposalCreated( uint256 porposalId, address proposer, string communityName, IncentiveStructure structure, uint256 communityFee, address payable contractRecieveAddress);
    event IncetniveParamsUpdated(string communityName, IncentiveStructure structure, uint256 communityFee, address payable contractRecieveAddress );
        
    //Functions

    /*
        * @notice Allows a member to create a proposal for community incentive.
        * @dev Allows owner to set their community incentive parameters initally. Never after (requires proposal)
        * @param _communityName Name of the community to set the conseous for.
        * @param _structure Type of incentive structure.
        * @param _communityFee Percentage of the community to recieve the incentive.
        * @param _contractRecieveAddress Address to recieve the incentive.

    */
   function setParams(     
        string memory _communityName,   
        IncentiveStructure _structure,
        uint256 _communityFee,
        address payable _contractRecieveAddress
        ) external returns(bool){
        
        require(CommunityContract.getCommunityOwner(_communityName) == msg.sender, "User is not the owner of this community");
        require(IncentiveStructures[_communityName].isSet == false, "Parameters already set");

        if (_communityFee > 0) {
            require(_contractRecieveAddress != payable(address(0)), "Sending address cannot be 0");
        }    
        IncentiveParams storage iP = IncentiveStructures[_communityName];

        iP.structure = _structure;
        iP.communityFee = _communityFee;
        iP.contractRecieveAddress= _contractRecieveAddress;
        iP.isSet = true;

        emit IncentiveStructureSet(_communityName, _structure, _communityFee, _contractRecieveAddress);
        return iP.isSet;
    }



    /*
        * @notice Allows a member to create a proposal for community incentive.
        * @dev Allows Members to Submit New Invetive Parameter Porposals
        * @param _communityName Name of the community to set the conseous for.
        * @param _structure Type of incentive structure.
        * @param _communityFee Percentage of the community to recieve the incentive.
        * @param _contractRecieveAddress Address to recieve the incentive.

    */

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

    function createProposal(
        string memory _communityName,   
        IncentiveStructure _structure,
        uint256 _communityFee,
        address payable _contractRecieveAddress
    )external payable returns(uint256){
        require(msg.value == totalFee, "Incorrect fee");

        if (_communityFee > 0) {
            require(_contractRecieveAddress != payable(address(0)), "Sending address cannot be 0");
        }        

        uint256 proposalId = CommunityContract.CustomProposal{value: TGcommunitiesFee}(_communityName, address(this));
        require(proposalId > 0, "Proposal not created");

        IncentiveProposal memory iPP = IncentiveProposals[proposalId];
        iPP.proposer = msg.sender;
        iPP.communityName = _communityName;
        iPP.structure = _structure;
        iPP.communityFee = _communityFee;
        iPP.contractRecieveAddress= _contractRecieveAddress;
        emit IncentiveProposalCreated(proposalId, msg.sender, _communityName, _structure, _communityFee, _contractRecieveAddress);
        
        bool _isFunded = FundContract.fundUpkeep{value: msg.value - TGcommunitiesFee}(address(this));
        if (_isFunded) {
            IncentiveProposals[proposalId] = iPP;
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

        if(_contractAddress == thisAddress && IncentiveProposals[_proposalId].proposer != address(0) && IncentiveProposals[_proposalId].upkeeped == false ){
            upkeepNeeded = true;
        }
        
        return (upkeepNeeded, abi.encode(_proposalId));


    }

    /*

        * @notice Performs the upkeep of the contract.
        * @dev Ensures the proposal exists in this contract and is not upkeeped.
        * @dev Ensures the proposal is no longer active and updates the community incetive params if passed.
        * @param _performData The bytes transformed proposal id to upkeep
    */
    function performUpkeep(bytes calldata _performData) external  {

        uint256 _proposalId = abi.decode(_performData, (uint256));

        if(IncentiveProposals[_proposalId].proposer != address(0)){
            (bool _isActive, bool _passed) = CommunityContract.getProposalResults(_proposalId);


            // We can use _isActive here because we already know the proposal exists, and when created is set to true
            if (_isActive == false){
                if (_passed){
                    IncentiveProposal memory iPP = IncentiveProposals[_proposalId];
                    iPP.upkeeped = true;
                    iPP.passed = true;
                    IncentiveProposals[_proposalId] = iPP;
                    IncentiveParams storage iP = IncentiveStructures[iPP.communityName];


                    iP.structure = iPP.structure;
                    iP.communityFee=  iPP.communityFee;
                    iP.contractRecieveAddress = iPP.contractRecieveAddress;

                    if (iP.isSet == false){
                        iP.isSet = true;
                    }

                    emit IncetniveParamsUpdated(iPP.communityName, iP.structure, iP.communityFee, iP.contractRecieveAddress);
                }else{
                    IncentiveProposal memory iPP = IncentiveProposals[_proposalId];
                    iPP.upkeeped = true;
                    iPP.passed = false;
                    IncentiveProposals[_proposalId] = iPP;
                }

            }
        }


    }



    // Helper Functions
    function bytes32ToAddress(bytes32 _address) public pure returns (address) {
        return address(uint160(uint256(_address)));
    }

    function getProposal(uint256 _proposalId) external view returns(IncentiveProposal memory){
        return IncentiveProposals[_proposalId];
    }


    function getParams(string memory _communityName) external view returns ( IncentiveStructure structure, uint256 _communityFee, address _contractRecieveAddress, bool _isSet){
        return (IncentiveStructures[_communityName].structure, IncentiveStructures[_communityName].communityFee, IncentiveStructures[_communityName].contractRecieveAddress, IncentiveStructures[_communityName].isSet);
    }


    function getIncentiveParamsExist(string memory _communityName) external view returns(bool _isSet){
        return (IncentiveStructures[_communityName].isSet);
    }

    function getInctiveStructure(string memory _communityName) external view returns(IncentiveStructure){
        return IncentiveStructures[_communityName].structure;
    }

    function getCommunityFeeInfo(string memory _communityName) external view returns(uint256 _communityFee, address _contractRecieveAddress){
        return (IncentiveStructures[_communityName].communityFee, IncentiveStructures[_communityName].contractRecieveAddress);
    }



    // Only Owner Funcitons

    function settgetherCommunityContract(address _contractAddress) external onlyOwner {
        CommunityContract= tgetherCommuunitiesInterfact(_contractAddress);

    }

    function setFee(uint256 _feePrice) external onlyOwner {
        fee= _feePrice;
    }

    function UpdateTotalFee() external onlyOwner {
        uint256 _comfee =CommunityContract.getFee();

        TGcommunitiesFee = _comfee;
        totalFee = fee + _comfee;
    }
    function setFundContract(address _contract) external onlyOwner {
       FundContract= tgetherFundInterface(_contract);

    }




}