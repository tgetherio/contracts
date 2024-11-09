// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "hardhat/console.sol";

// Interface for FundContract
interface FundContract {
    function fundUpkeep(address _contractAddress) external payable returns (bool);
}

// Interface for CommunitiesContract (to fetch post data)
interface PostConsensusInterface is AutomationCompatibleInterface {
    function getSubmissionExpiration(uint256 _submissionId) external view returns(uint256);
    function getCheckSubmissionForUpkeep(uint256 submissionId) external view returns (bool upkeepNeeded, int256 resultId);
    function performUpkeep(bytes calldata performData) external;
}

// Interface for the LaneRegistry to update lane size
interface LaneRegistryInterface {
    function reportLaneLength(uint256 laneId, uint256 newLength) external;
    function addLane(address _contractAddress) external  returns (uint256);
}

// CommunitiesLane Contract
contract PostConsensusLane  is AutomationCompatibleInterface {

    uint256[] public posts;  // Array to store post IDs
    mapping(uint256 => uint256) public postIndex;  // Mapping from postId to index in posts array
    address public owner;
    address public registry;
    address public postConsensus;
    address public laneRegistryContract;
    address public automationForwarder;

    uint256 public laneId;

    FundContract public fundContract;

    uint256 constant NOT_IN_MAPPING = type(uint256).max;  // Sentinel value for non-existent posts

    event IndexChange(uint256 postId, uint256 newIndex);  // Event to emit when an index changes
    event PostRemoved(uint256 postId);  // Event emitted when a post is removed

    constructor(address _fundContractAddress, address _postConsensus, address _laneRegistryContract) {
        owner = msg.sender;
        postConsensus = _postConsensus;
        laneRegistryContract = _laneRegistryContract;
        fundContract = FundContract(_fundContractAddress);
        laneId = LaneRegistryInterface(laneRegistryContract).addLane(address(this));
    }

    modifier ownerOnly() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier onlyRegistry() {
        require(msg.sender == laneRegistryContract, "Not the registry");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner || msg.sender == postConsensus, "Not authorized");
        _;
    }

    modifier onlyAutomationForwarder(){
        require(msg.sender == automationForwarder, "Not the automation forwarder");
        _;
    }



    // Append post ID to the lane (only callable by the registry)
    function appendToLane(uint256 postId) external payable onlyRegistry returns (uint256) {
        // Call the FundContract to handle the upkeep payment

        bool _isFunded = fundContract.fundUpkeep{value: msg.value}(address(this));
        require(_isFunded, "Upkeep payment failed");

        // Append the new post ID to the array and update the index mapping
        posts.push(postId);
        postIndex[postId] = posts.length - 1;  // Store the index of the new post

        // Return the new length of the lane
        return posts.length;
    }

    // Automated checkUpkeep function
    /*
     * @notice Checks if there are any submissions that need upkeep based on their review periods.
     * @param checkData Additional data passed to the function (not used in this implementation).
     * @return upkeepNeeded A boolean indicating if upkeep is needed.
     * @return performData Encoded data indicating the submission ID to be processed during performUpkeep.
     */

    function checkUpkeep(bytes calldata /* checkData */)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = false;
        uint256 lowestId = 0;

        if (posts.length > 0) {
            uint256 lowestTimestamp = 0;


            // Find the lowest expired submission
            for (uint256 i = 0; i < posts.length; i++) {
                uint256 submissionId = posts[i];
                uint256 reviewPeriodExpired = PostConsensusInterface(postConsensus).getSubmissionExpiration(submissionId);

                // Ensure review period is expired and is the lowest in the list
                if (reviewPeriodExpired <= block.timestamp && (reviewPeriodExpired <= lowestTimestamp || lowestTimestamp == 0)) {
                    upkeepNeeded = true;
                    lowestId = submissionId;
                    lowestTimestamp = reviewPeriodExpired;
                }
            }

            int256 resultId;

            if (lowestId != 0) {
                (upkeepNeeded,resultId) = PostConsensusInterface(postConsensus).getCheckSubmissionForUpkeep(lowestId);
                performData = abi.encode(resultId);
            }
        }
    }
    

    // Perform the upkeep (calls the Communities contract and then updates the lane size)
    function performUpkeep(bytes calldata _performData) external onlyAutomationForwarder{
        int256 resultId = abi.decode(_performData, (int256));
        uint256 postId;
        if (resultId < 0) {
            postId = uint256(-resultId);
        }else
        {
            postId = uint256(resultId);
        }

        // Call the Communities contract to perform the upkeep
        PostConsensusInterface(postConsensus).performUpkeep(_performData);

        // After upkeep, remove the post
        _removePost(postId);

        // Report the new lane length back to the registry
        LaneRegistryInterface(laneRegistryContract).reportLaneLength( laneId, posts.length);
    }

    // Internal function for removing a post
    function _removePost(uint256 postId) internal {
        uint256 indexToRemove = postIndex[postId];
        require(indexToRemove != NOT_IN_MAPPING || posts[0] == postId, "Post does not exist");

        uint256 lastpostIndex = posts.length - 1;
        uint256 lastPostId = posts[lastpostIndex];

        if (indexToRemove != lastpostIndex) {
            // Swap the post to remove with the last one
            posts[indexToRemove] = lastPostId;
            
            // Update the index in the mapping for the swapped post
            postIndex[lastPostId] = indexToRemove;

            // Emit event about index change
            emit IndexChange(lastPostId, indexToRemove);
        }

        // Remove the last element from the array
        posts.pop();
        postIndex[postId] = NOT_IN_MAPPING;  // Set the index to the sentinel value

        // Emit post removal event
        emit PostRemoved(postId);
    }

    // External call for the owner or communities contract to remove a post
    function removePost(uint256 postId) external onlyAuthorized {
        _removePost(postId);
        
    }

    // Getter to retrieve the post count
    function getPostCount() external view returns (uint256) {
        return posts.length;
    }

    // Getter to retrieve a specific post ID by index
    function getPostByIndex(uint256 index) external view returns (uint256) {
        require(index < posts.length, "Invalid index");
        return posts[index];
    }

    // Getter to retrieve the index of a post by ID
    function getpostIndex(uint256 postId) external view returns (uint256) {
        uint256 index = postIndex[postId];
        require(index != NOT_IN_MAPPING || posts[0] == postId, "Post does not exist");
        return index;
    }


    function setRegistry(address _registry) external ownerOnly {
        laneRegistryContract = _registry;
    }

    function setFundContract(address _fundContractAddress) external ownerOnly {
        fundContract = FundContract(_fundContractAddress);
    }
    function setForwarder(address _forwarder) external ownerOnly {
        automationForwarder = _forwarder;
    }

}
