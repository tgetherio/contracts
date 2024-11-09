// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "hardhat/console.sol";




interface tgetherCommunityConsensusInterface{
    function getCCParamsExist(string memory _communityName) external view returns (bool);
    function getCommunityConsensousTime(string memory _communityName) external view returns (uint256);
    function getCommunityConsensousTypes (string memory _communityName) external view returns (string[] memory consensusTypes);
    function getCommunityReviewParams (string memory _communityName) external view returns (uint256 numReviewsForAcceptance,uint256 credsNeededForReview,uint256 percentAcceptsNeeded);
}

interface tgetherMembersInterface{
    function getMemberCreds(address _memberAddress, string memory _communityName) external view returns (uint256 creds); 
}

interface tgetherPostsInterface{
    function getPostExists(uint256 _postId) external view returns(bool);
}

interface tgetherFundInterface{
        function fundUpkeep(address _contractAddress) external payable returns (bool);
    }

interface laneRegistryInterface{
    function appendToLane(uint256 proposalId) external payable returns (uint256);
    function getLaneContractAddress(uint256 laneId) external view returns (address);
}
interface LaneContractInterface{
    function removePost(uint256 proposalId) external;
    function getpostIndex(uint256 postId) external view returns (uint256); 
}
contract tgetherPostConsensus{
    enum Consensus { NotProcessed, Pending, Accepted, Rejected }

    struct CommunitySubmission{
        string communityName;
        uint256 timestamp;
        uint256 consensusTime;
        Consensus consensus;
    }
    mapping(uint256=> CommunitySubmission) public CommunitySubmissions; //csCounter=> SubjectSubmission
    mapping (uint256=>uint256) public CommunitySubmissionToPost; // communitySubmissionId => postID
    uint256 public csCounter;

    // mapping allows us to retrieve the community submissions for a specifc post
    mapping( uint256  => uint256[] ) public PostSubmissionList; // postId => communitySubmissionId

    // mapping allows us to retrieve the post submissions for a specific community
    mapping(uint256=> mapping(string => uint256)) public postCommunities; // postId => communityName => communitySubmissionId

    mapping(uint256=> uint256) public SubmissionLane; //communitySubmissionId => laneId

    struct Review{
        address member;
        string content;
        uint256 consensus;
        string consensusType;
        uint256 creds;
        bool afterConsensus;
    }


    mapping(uint256=> Review) public reviews; //reviewId => Review
    uint256 public reviewCounter;

    mapping(uint256=> uint256[]) public submmisionReviews; //communitySubmissionId => reviewId[]



    string[] defaultConsenousTypes = [ "Consensous Pending", "Accepted", "Rejected"];

    // mapping allows us to track if someone has already reviewed a post (avoid spam)
    mapping(uint256 => mapping(address => bool)) public hasReviewed; //communitySubmissionId => memberAddress => bool



    address AutomationContractAddress; 

    tgetherCommunityConsensusInterface public CommunityConsensusContract; 
    tgetherMembersInterface public MembersContract; 
    tgetherPostsInterface public PostsContract;
    
    address laneRegistry;

    uint256 public consensusFee;

    uint256 public maxReviews;  //We have a max reviews value to ensure to avoid spam reviews clogging active proposals
    address owner;


    modifier ownerOnly() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }   

    constructor(address _CommunityConsensusAddress, address _MembersContract, address _PostContract, uint256 _fee ) {
        owner= msg.sender;

        CommunityConsensusContract= tgetherCommunityConsensusInterface(_CommunityConsensusAddress);
        MembersContract= tgetherMembersInterface(_MembersContract);
        PostsContract= tgetherPostsInterface(_PostContract);

        consensusFee = _fee;

        reviewCounter= 1;
        csCounter = 1;

        maxReviews = 100;


    }



    

    // Events
    event PostSubmission(uint256 indexed postId, uint256 indexed communitySubmissionId);
    event CommunitySubmitted(uint256 indexed communtiySubmissionId, string indexed communityName, uint256 timestamp, uint256 consensusTime);
    event ReviewCreated(uint256 indexed reviewId, uint256 indexed communitySubmissionId, address indexed member);
    event ReviewSubmitted(uint256 indexed reviewId, string consensus, uint256 creds, string content, bool afterConsensus);
    event ConsensusUpdated(uint256 indexed communitySubmissionId, uint256 postId, string newConsensus);
    event Keywords(uint256 postId, string keyword);

    


    /*
    @notice Submits a post to a community for review
    @dev Checks if the post exists, if the post has already been submitted to the community, and if the community exists
    @param _postId uint256 post id to be submitted
    @param _communityName string name of the community to be updated.
    */

    /**
    * DISCLAIMER:
    * By signing and submitting this transaction, you acknowledge that you are contributing funds to a shared pool 
    * rather than directly funding your individual upkeep execution. This pooling mechanism is designed to optimize 
    * resource allocation and minimize transaction costs.
    *
    * Please be aware that price volatility may affect the availability of funds required to process your upkeep. 
    * In such cases, your upkeep may not be automatically executed. However, you retain the option to manually 
    * execute your upkeep at any time by calling the manualUpkeepPost function.
    *
    * Ensure you understand the risks associated with price fluctuations and the potential impact on the automatic 
    * processing of your upkeep.
    */

function submitToCommunity(uint256 _postId, string memory _communityName) external payable returns (uint256 )  {
    // Check if the post exists
    require(PostsContract.getPostExists(_postId), "Post does not exist");
    require(CommunityConsensusContract.getCCParamsExist(_communityName), "Community Consensus Params don't exist");
    uint256 consensusTime = CommunityConsensusContract.getCommunityConsensousTime(_communityName);

    CommunitySubmission memory newCommunitySubmission = CommunitySubmission({
        communityName: _communityName,
        timestamp: block.timestamp,
        consensusTime: consensusTime,
        consensus: Consensus.Pending
    });

    if (consensusTime == 0 ){
        // Create a new community submission where no active consensus is needed
        newCommunitySubmission.consensus = Consensus.NotProcessed;

    } else {
        // Charge a fee if consensus is needed
        require(msg.value == consensusFee, "Must send proposal fee");
        uint256 laneId = laneRegistryInterface(laneRegistry).appendToLane{value: msg.value}(csCounter);
        SubmissionLane[csCounter] = laneId;
    }

    // Use newCsCounter to store the current counter value and update mappings
    uint256 newCsCounter = csCounter;
    CommunitySubmissions[newCsCounter] = newCommunitySubmission;
    PostSubmissionList[_postId].push(newCsCounter);
    CommunitySubmissionToPost[newCsCounter] = _postId;
    postCommunities[_postId][_communityName] = newCsCounter;

    // Increment csCounter only once after all operations
    csCounter++;

    // Emit events using newCsCounter
    emit PostSubmission(_postId, newCsCounter);
    emit CommunitySubmitted(newCsCounter, _communityName, block.timestamp, consensusTime);

    return newCsCounter;
}



    /*
    * @notice Adds a review to the reviews array for a specific post
    * @notice Consous value 2 will accept a post anything else will reject it
    * @dev Review must be submitted by an active member. ConsenouType List is a mock concatonation of the default array with the community owned array
    * @param _postId uint256 post id review is attached to 
    * @param _content string content of the review content
    * @param _consensus uint256 the index of the consensus type of the mock concatonation of the default array with the community owned array 
    */


    function submitReview(uint256 _communitySubmissionId, string memory _content, uint256 _consensus) public returns(uint256){
        // Check if the submission exists
        require(CommunitySubmissions[_communitySubmissionId].timestamp != 0, "Submission does not exist");

                
        // Requirement must be in bounds of default array +custom community array 
        string[] memory  consensusTypes= CommunityConsensusContract.getCommunityConsensousTypes( CommunitySubmissions[_communitySubmissionId].communityName );
        require(_consensus > 1, "Consensous mus be greater than 1");
        require(_consensus <= defaultConsenousTypes.length + consensusTypes.length , "Consensous Not In Bounds");
        

        // Avoid Spam
        require(!hasReviewed[_communitySubmissionId][msg.sender], "You've already reviewed this post");
        hasReviewed[_communitySubmissionId][msg.sender] = true;


        // Check if the member has the necessary credentials
        uint256 creds = MembersContract.getMemberCreds(msg.sender, CommunitySubmissions[_communitySubmissionId].communityName);
        
        string memory consensusType;

        if (_consensus <= defaultConsenousTypes.length) {
            consensusType = defaultConsenousTypes[_consensus - 1]; // Adjust index by 1 
        } else {
            consensusType = consensusTypes[_consensus - defaultConsenousTypes.length - 1]; // Adjust index by 1
        }

        bool _afterConsensus;
        
        if (CommunitySubmissions[_communitySubmissionId].consensus != Consensus.Pending) {
            _afterConsensus = true;
        }

        // Create a new review
        Review memory newReview = Review({
            member: msg.sender,
            content: _content,
            consensus: _consensus,
            consensusType: consensusType,
            creds: creds,
            afterConsensus: _afterConsensus
        });


        reviews[reviewCounter] = newReview;
        submmisionReviews[_communitySubmissionId].push(reviewCounter);

        emit ReviewCreated(reviewCounter,_communitySubmissionId, msg.sender);


        // Add the review to the post's reviews
        emit ReviewSubmitted(reviewCounter, consensusType, creds, _content, _afterConsensus);

        reviewCounter++;

        return reviewCounter-1;


    }

    // Internal function to determine if a submission needs upkeep
    /**
     * @notice Checks if a specific submission requires upkeep based on its review period expiration and review consensus.
     * @param submissionId The ID of the submission to check for upkeep.
     * @return upkeepNeeded A boolean indicating whether the upkeep is needed for the given submission.
     * @return resultId An integer indicating the result of the review process: positive for acceptance, negative for rejection.
     */
    function _checkSubmissionForUpkeep(uint256 submissionId) internal view returns (bool upkeepNeeded, int256 resultId) {
        upkeepNeeded = false;
        resultId = 0;

        // Check if the review period has expired for the submission
        uint256 reviewPeriodExpired = CommunitySubmissions[submissionId].timestamp + CommunitySubmissions[submissionId].consensusTime;

        if (reviewPeriodExpired <= block.timestamp) {
            upkeepNeeded = true;
            resultId = _processReviews(submissionId);
        }
    }

    // Internal function to process reviews and determine consensus
    /**
     * @notice Processes the reviews for a given submission to determine whether it is accepted or rejected.
     * @param submissionId The ID of the submission being reviewed.
     * @return resultId An integer representing the outcome of the review process: positive for accepted, negative for rejected.
     */
    function _processReviews(uint256 submissionId) internal view returns (int256 resultId) {
        (uint256 numReviewsForAcceptance, uint256 credsNeededForReview, uint256 percentAcceptsNeeded) =
            CommunityConsensusContract.getCommunityReviewParams(CommunitySubmissions[submissionId].communityName);

        uint256[] memory reviewList = submmisionReviews[submissionId];

        // Check if there are enough reviews
        if (reviewList.length < numReviewsForAcceptance) {
            return int256(submissionId) * -1; // Rejected due to insufficient reviews
        }

        uint256 acceptedReviewsCount = 0;
        uint256 totalCount = 0;
        uint256 upperbound = reviewList.length > maxReviews ? maxReviews : reviewList.length;

        // Loop through the reviews to count the number of accepted and total reviews
        for (uint256 i = 0; i < upperbound; i++) {
            (uint256 reviewConsensus, uint256 reviewCreds, bool _afterConsensus) = this.getReviewConsenous(reviewList[i]);
            if (_afterConsensus) {
                continue;
            }
            if (reviewCreds >= credsNeededForReview) {
                totalCount++;
                if (reviewConsensus == 2) { // Assuming 2 indicates "Accepted"
                    acceptedReviewsCount++;
                }
            }
        }

        // Determine the acceptance status based on review counts
        if (totalCount == 0 || totalCount < numReviewsForAcceptance) {
            return int256(submissionId) * -1; // Rejected due to insufficient valid reviews
        }

        uint256 percentAcceptedByCount = (acceptedReviewsCount * 100) / totalCount;
        return percentAcceptedByCount >= percentAcceptsNeeded ? int256(submissionId) : int256(submissionId) * -1;
    }

    // Internal function to perform upkeep on a submission
    /**
     * @notice Updates the consensus status of a submission and manages the active submissions list.
     * @param resultId An integer indicating the result of the review process: positive for acceptance, negative for rejection.
     */
    function _performSubmissionUpkeep(int256 resultId) internal {
        bool isAccepted = resultId > 0;
        uint256 submissionId = isAccepted ? uint256(resultId) : uint256(-resultId);

        // Update the consensus status and manage the active submissions list
        if (
            submissionId != 0 &&
            block.timestamp >= CommunitySubmissions[submissionId].timestamp + CommunitySubmissions[submissionId].consensusTime &&
            CommunitySubmissions[submissionId].timestamp != 0
        ) {
            CommunitySubmissions[submissionId].consensus = isAccepted ? Consensus.Accepted : Consensus.Rejected;
            emit ConsensusUpdated(submissionId, CommunitySubmissionToPost[submissionId], CommunitySubmissions[submissionId].consensus == Consensus.Accepted ? "Accepted" : "Rejected");

            // Remove the submission from the active list

        }else {
            revert("Upkeep not needed for this submission");
        }
    }


  
    /**
     * @notice Performs the upkeep on a specific submission based on the result data from checkUpkeep.
     * @param performData Encoded data containing the submission result ID (positive for accepted, negative for rejected).
     */
    function performUpkeep(bytes calldata performData) external {
        require(performData.length == 32, "Invalid performData length");
        int256 resultId = abi.decode(performData, (int256));
        uint256 _submissionId;
        if(resultId < 0) {
            _submissionId = uint256(-resultId);
        }else{
            _submissionId = uint256(resultId);
        }
        address lane = laneRegistryInterface(laneRegistry).getLaneContractAddress(SubmissionLane[_submissionId]);
        require(msg.sender == lane, "Only lane contract can perform upkeep");
        require(LaneContractInterface(lane).getpostIndex(_submissionId) >= 0, "Submission does not exist in lane");

        _performSubmissionUpkeep(resultId);
    }

    // Manual upkeep function for processing a specific submission manually
    /**
     * @notice Manually processes upkeep for a specific submission to update its consensus status.
     * @param submissionId The ID of the submission to manually process for upkeep.
     */
    function manualUpkeepPost(uint256 submissionId) external {
        require(submissionId != 0, "Invalid submission ID");
        require(
            CommunitySubmissions[submissionId].timestamp != 0,
            "Submission does not exist or is not active"
        );

        // Use the same logic to check if the specific submission needs upkeep
        (bool upkeepNeeded, int256 resultId) = _checkSubmissionForUpkeep(submissionId);

        require(upkeepNeeded, "Upkeep not needed for this submission");

        // Perform upkeep manually
        _performSubmissionUpkeep(resultId);
        uint256 _submissionId;
        if(resultId < 0) {
            _submissionId = uint256(-resultId);
        }else{
            _submissionId = uint256(resultId);
        }
        address lane = laneRegistryInterface(laneRegistry).getLaneContractAddress(SubmissionLane[_submissionId]);
        LaneContractInterface(lane).removePost(_submissionId);
    }

    function getCheckSubmissionForUpkeep(uint256 submissionId) external view returns (bool upkeepNeeded, int256 resultId) {
        return _checkSubmissionForUpkeep(submissionId);
    }




            
    // Getters



    function getCommunitySubmission(uint256 _communitySubmissionId) external view returns(CommunitySubmission memory){
        return CommunitySubmissions[_communitySubmissionId];
    }
    function getReviewsForSubmission(uint256 _submissionId) external view returns (uint256[] memory) {
        return submmisionReviews[_submissionId];
    }
    function getPostSubmissionList(uint256 _postId) public view returns (uint256[] memory) {
        return PostSubmissionList[_postId];
    }
    function getPostConsesous(uint256 _submissionId) external view returns (Consensus) {
        require(CommunitySubmissions[_submissionId].timestamp != 0, "Submission does not exist");
        return CommunitySubmissions[_submissionId].consensus;
    }
    function getReview(uint256 _reviewId) external view returns(Review memory){
        return reviews[_reviewId];
    }

    function getReviewConsenous(uint256 _reviewid) external view returns(uint256 consensus, uint256 creds, bool afterConsensus){
        return(reviews[_reviewid].consensus, reviews[_reviewid].creds, reviews[_reviewid].afterConsensus);
    }

    function getPostSubmissionCommunity(uint256 _postId) external view returns(string memory){
        return CommunitySubmissions[_postId].communityName;
    }
    function getPostSubmissionConsensus(uint256 _postId) external view returns(string memory){
        return CommunitySubmissions[_postId].communityName;
    }

    function getSubmissionExpiration(uint256 _submissionId) external view returns(uint256){
        return CommunitySubmissions[_submissionId].timestamp + CommunitySubmissions[_submissionId].consensusTime;
    }




    // Only Owner Funcitons
    function setAutomationRegistry(address _contractAddress) external ownerOnly {
        AutomationContractAddress= _contractAddress;

    }

    function setCommunitiesContract(address _contractAddress) external ownerOnly {
        CommunityConsensusContract= tgetherCommunityConsensusInterface(_contractAddress);
    }

    function setMembersContract(address _contractAddress) external ownerOnly {
        MembersContract= tgetherMembersInterface(_contractAddress);

    }



    function setFee(uint256 _feePrice) external ownerOnly {
        consensusFee= _feePrice;

    }


    function setdefaultConsenousTypes(string[] memory _deafultArray) external ownerOnly{
        defaultConsenousTypes= _deafultArray;
    }

    function setMaxReviews(uint256 _maxreviews) external ownerOnly {
        maxReviews= _maxreviews;

    }

    function setPostsContract(address _contractAddress) external ownerOnly {
        PostsContract= tgetherPostsInterface(_contractAddress);

    }

    function setLaneRegistry(address _contract) external ownerOnly {
        laneRegistry= _contract;
    }




}
