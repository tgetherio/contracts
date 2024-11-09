// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface LaneRegistryInterface {
    function reportLaneLength(uint256 laneId, uint256 newLength) external;
}
contract MockLaneContract {
    uint256 public laneLength;

    function appendToLane(uint256 id) external payable returns (uint256) {
        id = id;
        laneLength += 1;
        return laneLength;
    }

    function getLaneLength() external view returns (uint256) {
        return laneLength;
    }

    function performUpkeep() external {
        // Perform upkeep logic (if needed)
    }

    // Function to report lane length to the LaneRegistry
    function reportLaneLengthToRegistry(address registry, uint256 laneId, uint256 newLength) external {
        laneLength = newLength;
        LaneRegistryInterface(registry).reportLaneLength(laneId, newLength);
    }
}


