// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

// Interface for FundContract
interface FundContract {
    function fundUpkeep(address _contractAddress) external payable returns (bool);
}

// Interface for CommunitiesContract (to fetch proposal data)
interface CommunitiesContract is AutomationCompatibleInterface {

    function getVoteEnd(uint256 _propId) external view returns(uint256);

    function performUpkeep(bytes calldata performData) external;
}

// Interface for the LaneRegistry to update lane size
interface LaneRegistryInterface {
    function reportLaneLength(uint256 laneId, uint256 newLength) external;
    function addLane(address _contractAddress) external  returns (uint256);
}

// CommunitiesLane Contract
contract CommunitiesLane {

    uint256[] public proposals;  // Array to store proposal IDs
    mapping(uint256 => uint256) public proposalIndex;  // Mapping from proposalId to index in proposals array
    address public owner;
    address public registry;
    address public communitiesContract;
    address public laneRegistryContract;


    uint256 public laneId;

    FundContract public fundContract;

    uint256 constant NOT_IN_MAPPING = type(uint256).max;  // Sentinel value for non-existent proposals

    event IndexChange(uint256 proposalId, uint256 newIndex);  // Event to emit when an index changes
    event ProposalRemoved(uint256 proposalId);  // Event emitted when a proposal is removed

    constructor(address _fundContractAddress, address _communitiesContractAddress, address _laneRegistryContract) {
        owner = msg.sender;
        communitiesContract = _communitiesContractAddress;
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
        require(msg.sender == owner || msg.sender == communitiesContract, "Not authorized");
        _;
    }


    // Append proposal ID to the lane (only callable by the registry)
    function appendToLane(uint256 proposalId) external payable onlyRegistry returns (uint256) {
        // Call the FundContract to handle the upkeep payment

        bool _isFunded = fundContract.fundUpkeep{value: msg.value}(address(this));
        require(_isFunded, "Upkeep payment failed");

        // Append the new proposal ID to the array and update the index mapping
        proposals.push(proposalId);
        proposalIndex[proposalId] = proposals.length - 1;  // Store the index of the new proposal

        // Return the new length of the lane
        return proposals.length;
    }

    // Logic for Chainlink Automation to check if upkeep is needed
    function checkUpkeep(bytes calldata /*checkData*/) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = false;
        uint256 lowestId = 0;
        uint256 lowestVoteEnd = 0;

        // Loop through each proposal stored in this lane
        for (uint256 i = 0; i < proposals.length; i++) {
            uint256 proposalId = proposals[i];

            // Fetch proposal details from the external CommunitiesContract
            uint256 voteEnd = CommunitiesContract(communitiesContract).getVoteEnd(proposalId);

            // Check if voting has ended and whether it's the earliest (lowest voteEnd)
            if (voteEnd <= block.timestamp && (voteEnd <= lowestVoteEnd || lowestVoteEnd == 0)) {
                upkeepNeeded = true;
                lowestId = proposalId;
                lowestVoteEnd = voteEnd;
            }
        }

        // Return if upkeep is needed and which proposal to perform upkeep on
        return (upkeepNeeded, abi.encode(lowestId));
    }

    // Perform the upkeep (calls the Communities contract and then updates the lane size)
    function performUpkeep(bytes calldata _performData) external {
        uint256 proposalId = abi.decode(_performData, (uint256));

        // Call the Communities contract to perform the upkeep
        CommunitiesContract(communitiesContract).performUpkeep(_performData);

        // After upkeep, remove the proposal
        _removeProposal(proposalId);

        // Report the new lane length back to the registry
        LaneRegistryInterface(laneRegistryContract).reportLaneLength( laneId, proposals.length);
    }

    // Internal function for removing a proposal
    function _removeProposal(uint256 proposalId) internal {
        uint256 indexToRemove = proposalIndex[proposalId];
        require(indexToRemove != NOT_IN_MAPPING || proposals[0] == proposalId, "Proposal does not exist");

        uint256 lastProposalIndex = proposals.length - 1;
        uint256 lastProposalId = proposals[lastProposalIndex];

        if (indexToRemove != lastProposalIndex) {
            // Swap the proposal to remove with the last one
            proposals[indexToRemove] = lastProposalId;
            
            // Update the index in the mapping for the swapped proposal
            proposalIndex[lastProposalId] = indexToRemove;

            // Emit event about index change
            emit IndexChange(lastProposalId, indexToRemove);
        }

        // Remove the last element from the array
        proposals.pop();
        proposalIndex[proposalId] = NOT_IN_MAPPING;  // Set the index to the sentinel value

        // Emit proposal removal event
        emit ProposalRemoved(proposalId);
    }

    // External call for the owner or communities contract to remove a proposal
    function removeProposal(uint256 proposalId) external onlyAuthorized {
        _removeProposal(proposalId);
    }

    // Getter to retrieve the proposal count
    function getProposalCount() external view returns (uint256) {
        return proposals.length;
    }

    // Getter to retrieve a specific proposal ID by index
    function getProposalByIndex(uint256 index) external view returns (uint256) {
        require(index < proposals.length, "Invalid index");
        return proposals[index];
    }

    // Getter to retrieve the index of a proposal by ID
    function getProposalIndex(uint256 proposalId) external view returns (uint256) {
        uint256 index = proposalIndex[proposalId];
        require(index != NOT_IN_MAPPING || proposals[0] == proposalId, "Proposal does not exist");
        return index;
    }


    function setRegistry(address _registry) external ownerOnly {
        laneRegistryContract = _registry;
    }

    function setFundContract(address _fundContractAddress) external ownerOnly {
        fundContract = FundContract(_fundContractAddress);
    }

}
