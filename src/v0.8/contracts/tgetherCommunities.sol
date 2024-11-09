// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "hardhat/console.sol";

interface tgetherMembersInterface{
    function getMemberCreds(address _member, string memory _community) external view returns (int256 creds); 
    function getIsMember(address _member, string memory _community) external view returns (bool);
    }

interface laneRegistryInterface{
    function appendToLane(uint256 proposalId) external payable returns (uint256);
    function getLaneContractAddress(uint256 laneId) external view returns (address);
}
interface LaneContractInterface{
    function removeProposal(uint256 proposalId) external;
}


contract tgetherCommunities{

    struct Community  {
        address creator;
        uint256 minCredsToProposeVote;        // Minimum creds needed to propose a vote
        uint256 minCredsToVote;               // Minimum creds required to vote
        uint256 maxCredsCountedForVote;       // Maximum creds that can be counted for a vote
        uint256 minProposalVotes;
        address memberAccessContract;          // For Advanced Use * allows for a contract to control member access * should be audited and tested before *
        uint256 proposalTime;
        uint256 proposalDelay;
        bool isInviteOnly;    
        }

    mapping(string => Community) public communities;

    string[] public CommunityNames;



    struct ProposalProp{
        uint256 minCredsToProposeVote;        // Minimum creds needed to propose a vote
        uint256 minCredsToVote;               // Minimum creds required to vote
        uint256 maxCredsCountedForVote;       // Maximum creds that can be counted for a vote
        uint256 minProposalVotes;
        address memberAccessContract;              // For Advanced Use * allows for a contract to control cred access * should be audited and tested before 
        uint256 proposalTime;
        uint256 proposalDelay;
        bool isInviteOnly;
    }
    mapping(uint256=> ProposalProp) public CommunityProposals;


    uint256 maxProposalTime; // Variable used to set a maximum amount proposalTime can be

    struct Proposal {
        address proposer;
        string communityName;
        uint256 timestamp;
        uint256 propType; // 1 for community 2 for Custom Proposals
        uint256 laneId;
        uint256 approveVotes;
        uint256 denyVotes;
        uint256 approveCreds;
        uint256 denyCreds;
        mapping(address => bool) votes; // to track which members have voted true for approve false for deny
        bool isActive;
        bool passed;
    }
    
    mapping(uint256 => address) public CustomProposals; // For Custom Proposals. Use Event Logs index to upkeep on target contract
        // Custom proposalId => address of contract to upkeep

    uint256 proposalCounter;
    mapping(uint256=> Proposal) public proposals;

    mapping(string => uint256[]) public porposalsByCommunity;
    mapping(address=>bool) public hasOpenProposal;

    address private owner;
    uint256 public fee;

    tgetherMembersInterface public MemberContract;
    laneRegistryInterface public laneRegistryContract;

    uint256 public upkeepId;
    constructor(uint256 _feePrice) {
        owner = msg.sender;

        fee = _feePrice;

        // Array Time Dependent variables set to 3 months by default can be changed by setters
        maxProposalTime = 7890000;

        proposalCounter = 1;
    }


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier proposalRequirements(string memory _communityName){
        // // Ensure the community exists
        require(communities[_communityName].creator != address(0), "Community doesn't exist");
        // // Ensure the proposer does not have an open proposal
        require(!hasOpenProposal[tx.origin], "User has Open Review, Please wait untill it is processed.");
        // // Ensure the proposer is a member of the communities and has enough creds

        require(MemberContract.getIsMember(tx.origin, _communityName) == true, "You are not a member for this community.");
        // //Make sure creds are enough to propose
        
        require(MemberContract.getMemberCreds(tx.origin, _communityName) >= int256(communities[_communityName].minCredsToProposeVote), "Insufficient creds to propose.");
        // // Ensure the proposer has paid the fee to cover upkeep 

        require(msg.value == fee, "Must send proposal fee");
        _;
    }

    // Events 
    
    event CommunityCreated(string indexed communityName, address creator, bool isInviteOnly);
    event CommunityInfo(string indexed communityName, uint256 minCredsToProposeVote, uint256 minCredsToVote, uint256 maxCredsCountedForVote, uint256 minProposalVotes,address memberAccessContract, uint256 proposalTime,uint256 proposalDelay,bool isInviteOnly );
    event CommunityProposalParams(string indexed communityName, uint256 indexed proposalId, uint256 minCredsToProposeVote, uint256 minCredsToVote, uint256 maxCredsCountedForVote, uint256 minProposalVotes, address memberAccessContract, uint256 proposalTime, uint256 proposalDelay, bool isInviteOnly);  
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string indexed communityName, uint256 timestamp, uint256 propType);
    event CustomProposalCreated(address indexed contractAddress, uint256 indexed proposalId, address indexed proposer);
    event Voted(uint256 indexed proposalId, address indexed voter, bool indexed voteChoice, uint256 credsToCount);
    event ProposalResult(uint256 indexed proposalId, bool indexed passed);
    event CustomProposalResult(address indexed contractAddress, uint256 indexed proposalId, bool indexed passed);

    /*
        * @notice Creates a new community object in the system.
        * @dev Ensures the communities does not already exist.
        * @param _communityName Name of the communities to be created.
        * @param _numReviewsForAcceptance Number of reviews required for acceptance.
        * @param _credsNeededForReview Creds required for a review.
        * @param _percentAcceptsNeeded Percentage of accepts needed.
        * @param _minCredsToProposeVote Minimum creds required to propose a vote.
        * @param _minCredsToVote Minimum creds required to vote.
        * @param _maxCredsCountedForVote Maximum creds that can be counted for a vote.
        * @param _minProposalVotes Minimum proposal votes required.
    */
    function createCommunity(
        string memory _communityName,
        uint256 _minCredsToProposeVote,
        uint256 _minCredsToVote,
        uint256 _maxCredsCountedForVote,
        uint256 _minProposalVotes,
        address _memberAccessContract,
        uint256 _proposalTime,
        uint256 _proposalDelay,
        bool _isInviteOnly
    ) public  {

        // Ensure Community Does not exsist

        require(communities[_communityName].creator == address(0), "Community already exists.");

        if (_proposalTime > maxProposalTime){
            _proposalTime = maxProposalTime;
        }

        // Add Parameters

        communities[_communityName].creator = msg.sender;
        communities[_communityName].minCredsToProposeVote = _minCredsToProposeVote;
        communities[_communityName].minCredsToVote = _minCredsToVote;
        communities[_communityName].maxCredsCountedForVote = _maxCredsCountedForVote;
        communities[_communityName].minProposalVotes= _minProposalVotes;
        communities[_communityName].memberAccessContract= _memberAccessContract;
        communities[_communityName].proposalTime = _proposalTime;
        communities[_communityName].proposalDelay = _proposalDelay;

        communities[_communityName].isInviteOnly = _isInviteOnly;


        CommunityNames.push(_communityName);
        
        emit CommunityCreated(_communityName, msg.sender, _isInviteOnly);
        emit CommunityInfo(_communityName, _minCredsToProposeVote, _minCredsToVote, _maxCredsCountedForVote, _minProposalVotes,_memberAccessContract, _proposalTime, _proposalDelay, _isInviteOnly);


    }


    /*
        * @notice Creates a new proposal object in the system.
        * @dev Ensures the proposal does not already exist.
        * @param _communityName Name of the communities to be updated.
        * @param _propType Type of proposal to be created.
        * @return proposalCounter ID of the proposal.
    */
    function createProposal(string memory _communityName, uint256 _propType) internal returns(uint256){
        // Create a new proposal using the proposalCounter as an ID

        Proposal storage prop = proposals[proposalCounter];
        prop.proposer = tx.origin;
        prop.communityName= _communityName;
        prop.timestamp= block.timestamp;
        prop.propType= _propType;
        prop.isActive= true;

        emit ProposalCreated(proposalCounter, msg.sender, _communityName, block.timestamp, _propType);

        porposalsByCommunity[_communityName].push(proposalCounter);

        return proposalCounter;

    }





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
    function CommunityProposal(
        string memory _communityName,
        uint256 _minCredsToProposeVote,
        uint256 _minCredsToVote,
        uint256 _maxCredsCountedForVote,
        uint256 _minProposalVotes,
        address _credsAccessAddress,
        uint256 _proposalTime,
        uint256 _proposalDelay,
        bool _isInviteOnly
     ) external payable proposalRequirements(_communityName) returns(uint256){

        // Create a new proposal using the proposalCounter as an ID
        ProposalProp storage pProp = CommunityProposals[proposalCounter];

        // Adjust our array time dependent variables to avoid clog 
        if (_proposalTime > maxProposalTime){
            _proposalTime = maxProposalTime;
        }

        // create our generic proposal
        createProposal(_communityName, 1);

        pProp.minCredsToProposeVote = _minCredsToProposeVote;
        pProp.minCredsToVote = _minCredsToVote;
        pProp.maxCredsCountedForVote = _maxCredsCountedForVote;
        pProp.minProposalVotes = _minProposalVotes;
        pProp.memberAccessContract = _credsAccessAddress;
        pProp.proposalTime = _proposalTime;
        pProp.proposalDelay = _proposalDelay;
        pProp.isInviteOnly = _isInviteOnly;

        emit CommunityProposalParams(_communityName, proposalCounter, _minCredsToProposeVote, _minCredsToVote, _maxCredsCountedForVote, _minProposalVotes, _credsAccessAddress, _proposalTime, _proposalDelay, _isInviteOnly);

        uint256 laneId = laneRegistryContract.appendToLane{value: msg.value}(proposalCounter);
        proposals[proposalCounter].laneId = laneId;
    
        // Increment the proposalCounter
        proposalCounter++;  
        return proposalCounter-1;
    }


    /*
    * @notice Proposes changes to a communities's parameters. (Type 3)
    * @dev Ensures the communities exists and the proposer meets the requirements. Must Approve LinkFee to Contract before calling.
    * @param _communityName Name of the communities to be updated.
    * @param _contractAddress Address of the contract to upkeep.
    * @return proposalId ID of the proposal.
    */

     // We use tx.orgin here instead of msg.sender because this can be called by a contract and we want to track the user who called the contract


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

    function CustomProposal(
        string memory _communityName,
        address _contractAddress
    )external payable proposalRequirements(_communityName) returns(uint256){
        // create our generic proposal
        createProposal(_communityName, 2);

        // Set the external contract address so 3rd party upkeeps can keep track of it
        CustomProposals[proposalCounter] = _contractAddress;

        emit CustomProposalCreated(_contractAddress, proposalCounter, tx.origin);
        
        uint256 laneId = laneRegistryContract.appendToLane{value: msg.value}(proposalCounter);
        proposals[proposalCounter].laneId = laneId;
    


        // Increment the proposalCounter
        proposalCounter++;  
        return proposalCounter-1;

    }



    /*

        * @notice Allows a member to vote on a proposal.
        * @dev Ensures the proposal exists and the voter meets the requirements.
        * @param proposalId ID of the proposal to vote on.
        * @param voteChoice Choice of the voter (true for approve, false for deny).
    */
    function vote(uint256 proposalId, bool voteChoice) external {
        // Ensure the proposal exists
        require(proposalId < proposalCounter, "Proposal does not exist.");

        // Ensure The Proposal is Active

        Proposal storage proposal = proposals[proposalId];
        require(proposal.isActive == true, "Proposal is no longer Active");
        
        // Before delay period after experation
        require (block.timestamp >= proposal.timestamp + communities[proposal.communityName].proposalDelay && block.timestamp <= proposal.timestamp+ communities[proposal.communityName].proposalDelay + communities[proposal.communityName].proposalTime, "Not Active Voting Time");

        // Ensure the voter is a member for the communities
        require(MemberContract.getIsMember(msg.sender, proposal.communityName) == true, "You are not a member of this community.");

        // Ensure the voter has not voted before
        require(!proposal.votes[msg.sender], "You have already voted.");


        // Ensure the voter has more creds than the minCredsToVote
        int256 voterCreds = MemberContract.getMemberCreds(msg.sender, proposal.communityName);

        require(voterCreds >= int256(communities[proposal.communityName].minCredsToVote), "Insufficient creds to vote.");


        // Determine the amount of creds to count for the vote
        uint256 credsToCount = (voterCreds > int256(communities[proposal.communityName].maxCredsCountedForVote)) ? communities[proposal.communityName].maxCredsCountedForVote : uint256(voterCreds);
        

        if (voteChoice) {
            // If vote is true, add to approvevotes and approvecreds
            proposal.approveVotes += 1;
            proposal.approveCreds += credsToCount;
        } else {
            // If vote is false, add to denyvotes and deny creds
            proposal.denyVotes += 1;
            proposal.denyCreds += credsToCount;

        }

        // Mark the voter as having voted
        proposal.votes[msg.sender] = true;        

        emit Voted(proposalId, msg.sender, voteChoice, credsToCount);
    }



    /*
   * @notice Performs the upkeep of proposals.
   * @dev Validates that a proposal vote period has ended. If it is we check if the passed. If it does we set our communities values to the proposed ones. Then we set the proposal to inactive and swap-pop the ActiveProposals array
   * @param performData Data from the checkUpKeep function Proposal Id where vote period has ending
    */

    function performUpkeep(bytes calldata _performData) external {
        uint256 proposalId= abi.decode(_performData, (uint256));

        uint256 voteEnd= proposals[proposalId].timestamp + communities[proposals[proposalId].communityName].proposalDelay + communities[proposals[proposalId].communityName].proposalTime;

        // Proposal Id should never be 0 because we start the counter at 1, it should be after the vote end, and vote end shouldnt be 0 (someone  put in an id that isnt used yet)
        if ( proposalId != 0 && voteEnd <= block.timestamp  && voteEnd != 0){

            Proposal storage proposalToCheck = proposals[proposalId];
            
            // Check if the proposal has more approve votes than deny votes and more approve creds than deny creds or both cred amounts are 0 (when maxCredsCountedForVote is set to 0)
            if ( (proposalToCheck.approveVotes > proposalToCheck.denyVotes) && (proposalToCheck.approveCreds > proposalToCheck.denyCreds || communities[proposalToCheck.communityName].maxCredsCountedForVote == 0 ) && (proposalToCheck.approveVotes + proposalToCheck.denyVotes >= communities[proposalToCheck.communityName].minProposalVotes) ){
                // Update the communities's variables with the proposal's values
                if (proposalToCheck.propType ==2) {
                    emit CustomProposalResult(CustomProposals[proposalId], proposalId, true);
                }
                else if(proposalToCheck.propType ==1){
                        
                    Community storage communityToUpdate = communities[proposalToCheck.communityName];

                    communityToUpdate.minCredsToProposeVote = CommunityProposals[proposalId].minCredsToProposeVote;
                    communityToUpdate.minCredsToVote = CommunityProposals[proposalId].minCredsToVote;
                    communityToUpdate.maxCredsCountedForVote = CommunityProposals[proposalId].maxCredsCountedForVote;
                    communityToUpdate.minProposalVotes = CommunityProposals[proposalId].minProposalVotes;
                    communityToUpdate.memberAccessContract = CommunityProposals[proposalId].memberAccessContract;
                    communityToUpdate.proposalTime = CommunityProposals[proposalId].proposalTime;
                    communityToUpdate.proposalDelay = CommunityProposals[proposalId].proposalDelay;
                    communityToUpdate.isInviteOnly = CommunityProposals[proposalId].isInviteOnly;
                
                }


                emit ProposalResult(proposalId, true);
                proposals[proposalId].passed = true;

            }
            else{
                 proposals[proposalId].passed = false;
                emit ProposalResult(proposalId, false);

                if (proposalToCheck.propType ==2) {
                    emit CustomProposalResult(CustomProposals[proposalId], proposalId, false);
                }

            }
            //Allow user to propose again
            hasOpenProposal[proposalToCheck.proposer]= false;

            // Set proposal to inactive
            proposals[proposalId].isActive = false;

        }

    }
    /*
        * @notice Allows a member to cancel a proposal. 
        * @dev Ensures the proposal exists and the member is the proposer.
        * @param _propId ID of the proposal to cancel.
    */

    function setProposalCanceled(uint256 _propId) external  {
        require(proposals[_propId].proposer == msg.sender, "User did not propose this");
        require(proposals[_propId].isActive == true, "This proposal is not active");

        address _address = laneRegistryContract.getLaneContractAddress(proposals[_propId].laneId);
        LaneContractInterface(_address).removeProposal(_propId);
    }


    /*
        * @notice Allows a member to join a communities.
        * @dev Ensures the communities exists and the member meets the requirements.
        * @param _communityName Name of the communities to join.
    */
    function changeCommunityOwner(string memory _communityName, address _newOwner) external {
        require(communities[_communityName].creator == msg.sender, "User is not the owner of this community");
        communities[_communityName].creator = _newOwner;
    }






    // Only Owner Funcitons

    function settgetherMembersContract(address _contractAddress) external onlyOwner {
        MemberContract= tgetherMembersInterface(_contractAddress);

    }

    function setFee(uint256 _feePrice) external onlyOwner {
        fee= _feePrice;
    }

    function setUpkkepId(uint256 _upkeepId) external onlyOwner {
        upkeepId= _upkeepId;

    }
    function setProposalCounter(uint256 _count) external onlyOwner {
        proposalCounter= _count;

    }

    // To be used for testing/to unclog active proposal
    function setProposalInactive(uint256 _proposalId) external onlyOwner {
       proposals[_proposalId].isActive= false;

    }

    function setMaxProposalTime(uint256 _mpt) external onlyOwner {
       maxProposalTime= _mpt;

    }

    function setLaneRegistryContract(address _contractAddress) external onlyOwner {
        laneRegistryContract= laneRegistryInterface(_contractAddress);

    }



    // Getters
    function getCommunityExists(string memory _communityName) external view returns (bool){
        return communities[_communityName].creator != address(0);

    }
    function getCommunityInfo(string memory _communityName) external view returns (uint256 minCredsToProposeVote, uint256 minCredsToVote, uint256 maxCredsCountedForVote, uint256 minProposalVotes,uint256 proposalTime,uint256 proposalDelay,bool isInviteOnly){
        require(communities[_communityName].creator!= address(0), "Community Does Not Exsist");
        return( communities[_communityName].minCredsToProposeVote, communities[_communityName].minCredsToVote, communities[_communityName].maxCredsCountedForVote, communities[_communityName].minProposalVotes, communities[_communityName].proposalTime, communities[_communityName].proposalDelay, communities[_communityName].isInviteOnly);
    
    }
    function getMemberAccessContract(string memory _communityName) external view returns (address){
        require(communities[_communityName].creator!= address(0), "Community Does Not Exsist");
        return( communities[_communityName].memberAccessContract);
    }


    function getProposalVote(address _address, uint256 _proposalId ) external view returns (uint256 approveVotes, uint256 approveCreds, uint256 denyVotes, uint256 denyCreds, bool ) {
        // checks if a person has voted not what they voted for. To check what they coted for will need to use 
        return (proposals[_proposalId].approveVotes, proposals[_proposalId].approveCreds, proposals[_proposalId].denyVotes, proposals[_proposalId].denyCreds, proposals[_proposalId].votes[_address]);
    }

    function getProposalResults( uint256 _proposalId ) external view returns (bool isActive, bool passed ) {
        return ( proposals[_proposalId].isActive, proposals[_proposalId].passed);
    }
    
    function getLaneId(uint256 _propId)external view returns(uint256){
        return(proposals[_propId].laneId);
    }

    function getVoteEnd(uint256 _propId) external view returns(uint256){
        return(proposals[_propId].timestamp + communities[proposals[_propId].communityName].proposalDelay + communities[proposals[_propId].communityName].proposalTime);
    }

    function getCommunityOwner(string memory _communityName) external view returns (address){
        require(communities[_communityName].creator!= address(0), "Community Does Not Exsist");
        return communities[_communityName].creator;
    }
    function getCommunityIsOwner(string memory _communityName, address _add) external view returns (bool){
        require(communities[_communityName].creator!= address(0), "Community Does Not Exsist");
        return communities[_communityName].creator == _add ;
    }
    function getCommunityIsInviteOnly(string memory _communityName) external view returns(bool){
        require(communities[_communityName].creator!= address(0), "Community Does Not Exsist");
        return communities[_communityName].isInviteOnly;
    }
    

    function getProposalType(uint256 _proposalId) external view returns(uint256){
        return proposals[_proposalId].propType;
    }
    
    function getFee() external view returns(uint256){
        return fee;
    }

    function getPaginatedCommunityProposals(string memory _communityName, uint256 _numIdsreturned, uint256 _pageNumber ) external view returns(uint256[] memory, uint256 numPages){
        uint256[] memory ids = new uint256[](_numIdsreturned);
        uint256 counter= 0;
        uint256 start= _pageNumber * _numIdsreturned;
        uint256 end= start + _numIdsreturned;
        if (end > porposalsByCommunity[_communityName].length){
            end= porposalsByCommunity[_communityName].length;
        }
        for (uint256 i= start; i < end; i++){
            ids[counter]= porposalsByCommunity[_communityName][i];
            counter++;
        }
        return(ids, porposalsByCommunity[_communityName].length / _numIdsreturned);
    }


}