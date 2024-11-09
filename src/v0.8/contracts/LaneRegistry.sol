// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";

// Lane Contract Interface
interface LaneContract {
    function appendToLane(uint256 id) external payable returns (uint256);  // Payable to accept fee for upkeep
    function getLaneLength() external view returns (uint256);
    function performUpkeep() external;
    function reportLaneLength() external;
}

// CommunitiesLaneRegistry Contract
contract LaneRegistry {

    struct lane {
        address contractAddress;
        uint256 laneLength;
    }

    uint256[] public zeroLengthArray;  // Holds lanes with zero proposals
    mapping(uint256 => lane) public laneMap;

    mapping(address => uint256) public laneAddresses;

    address public owner;
    uint256 public laneCount;
    address public intakeContract;

    uint256 public lowestLaneLengthId;  // Tracks the lane with the lowest length

    constructor(address _contractAddress) {
        owner = msg.sender;
        laneCount = 1;
        intakeContract = _contractAddress;
        lowestLaneLengthId = 0;  // Initialize with no lanes as the lowest
    }

    modifier ownerOrigin() {
        require(tx.origin == owner, "Not the contract owner");
        _;
    }

    modifier intakeContractOnly() {
        require(msg.sender == intakeContract, "Not the intake contract");
        _;
    }



    // Add new lanes to the registry
    function addLane(address _contractAddress) external ownerOrigin  returns (uint256) {
        laneMap[laneCount] = lane(_contractAddress, 0);
        zeroLengthArray.push(laneCount);  // Since the new lane has zero proposals, add to zeroLengthArray

        laneAddresses[_contractAddress] = laneCount;
        if (lowestLaneLengthId != 0) {
            lowestLaneLengthId = laneCount;
        }

        laneCount++;

        return laneCount-1;
    }

    // Append a proposal to a lane (now payable to handle fees)
    function appendToLane(uint256 proposalId) external payable intakeContractOnly returns (uint256) {
        uint256 laneId;

        // Check if any lane is available in the zeroLengthArray
        if (zeroLengthArray.length > 0) {
            laneId = zeroLengthArray[zeroLengthArray.length - 1]; // Simply pop the last lane
            zeroLengthArray.pop();  // Remove the last element from zeroLengthArray
        } else {
            laneId = lowestLaneLengthId;  // Use the lane with the lowest length
        }

        // Append proposal to the selected lane and forward the value to the lane
        uint256 newLength = LaneContract(laneMap[laneId].contractAddress).appendToLane{value: msg.value}(proposalId);  // Forward the value (fee)

        // Update the internal length and lowest tracking


        reportLaneLengthInternal(laneId, newLength);
        return laneId;
    }

    function reportLaneLengthInternal(uint256 laneId, uint256 newLength) internal {
        laneMap[laneId].laneLength = newLength;

        // If the lane's length is zero, it should be added back to the zeroLengthArray
        if (newLength == 0) {
            zeroLengthArray.push(laneId);
        }

        // If the lane's length is less than the current lowest, update the lowest lane
        if (newLength < laneMap[lowestLaneLengthId].laneLength || laneMap[lowestLaneLengthId].laneLength == 0) {
            lowestLaneLengthId = laneId;
        }

    }

    // Lane reports back to the registry with its updated length
    function reportLaneLength(uint256 laneId, uint256 newLength) external {

        require(msg.sender == laneMap[laneId].contractAddress, "Not authorized to report");
        reportLaneLengthInternal(laneId, newLength);
    }

    function getLaneContractAddress(uint256 laneId) external view returns (address) {
        return laneMap[laneId].contractAddress;
    }

    function getIntakeContractAddress() external view returns (address) {
        return intakeContract;
    }
}
