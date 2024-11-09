// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ParameterGroupRegistry {
    function getParameterGroupExists(string memory _name) external view returns (bool);
    function incrementEnrollmentCount(string memory _name) external;
    function decrementEnrollmentCount(string memory _name) external;
}

interface CommunitiesInterface {
    function getCommunityExists(string memory _communityName) external view returns (bool);
    function getMemberAccessContract(string memory _communityName) external view returns (address);
    function getCommunityOwner(string memory _communityName) external view returns (address);
}

contract CommunityEnrollment {
    struct ParamGroupInfo {
        uint256 index;
        bool isEnrolled;
    }

    mapping(string => mapping(string => ParamGroupInfo)) public ParamGroupMapping; // Mapping of communities to parameter groups
    mapping(string => string[]) public CommunityParameterGroups; // List of parameter groups for each community

    ParameterGroupRegistry public registry;
    CommunitiesInterface public CommunitiesContract;
    address public owner;

    event CommunityEnrolled(string community, string parameterGroup);
    event CommunityUnenrolled(string community, string parameterGroup);

    constructor(address _registryAddress, address _communitiesContract) {
        require(_registryAddress != address(0), "Invalid registry address");
        require(_communitiesContract != address(0), "Invalid communities contract address");
        registry = ParameterGroupRegistry(_registryAddress);
        CommunitiesContract = CommunitiesInterface(_communitiesContract);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    function enrollCommunityInParameterGroup(string memory _community, string memory _parameterGroup) external {
        bool _exists = CommunitiesContract.getCommunityExists(_community);
        address _owner = CommunitiesContract.getCommunityOwner(_community);
        address _memberAccessContract = CommunitiesContract.getMemberAccessContract(_community);
        require(_exists, "Community does not exist");
        require(msg.sender == _owner || msg.sender == _memberAccessContract, "Only the community owner or Member Access Contract can enroll the community");

        require(ParamGroupMapping[_community][_parameterGroup].isEnrolled == false, "Community is already enrolled in this parameter group");
        require(registry.getParameterGroupExists(_parameterGroup), "Parameter group does not exist");

        // Add to the community's parameter group list
        if (CommunityParameterGroups[_community].length == 0) {
            CommunityParameterGroups[_community].push(""); // Ensure 0 index is reserved
        }
        CommunityParameterGroups[_community].push(_parameterGroup);

        uint256 index = CommunityParameterGroups[_community].length - 1;

        // Update the mapping
        ParamGroupMapping[_community][_parameterGroup] = ParamGroupInfo({
            index: index,
            isEnrolled: true
        });

        // Increment the enrollment count in the registry
        registry.incrementEnrollmentCount(_parameterGroup);

        emit CommunityEnrolled(_community, _parameterGroup);
    }

    function unenrollCommunityFromParameterGroup(string memory _community, string memory _parameterGroup) external {
        require(ParamGroupMapping[_community][_parameterGroup].isEnrolled, "Community is not enrolled in this parameter group");
        require(
            msg.sender == CommunitiesContract.getCommunityOwner(_community) ||
            msg.sender == CommunitiesContract.getMemberAccessContract(_community),
            "Only the community owner or Member Access Contract can unenroll the community"
        );

        uint256 index = ParamGroupMapping[_community][_parameterGroup].index;
        require(index > 0 && index < CommunityParameterGroups[_community].length, "Invalid index for unenrollment"); // index 0 is reserved for empty

        // Swap and pop to remove from the array
        uint256 lastIndex = CommunityParameterGroups[_community].length - 1;
        if (index != lastIndex) {
            CommunityParameterGroups[_community][index] = CommunityParameterGroups[_community][lastIndex];
            ParamGroupMapping[_community][CommunityParameterGroups[_community][index]].index = index;
        }
        CommunityParameterGroups[_community].pop();

        // Clear the mapping
        delete ParamGroupMapping[_community][_parameterGroup];

        // Decrement the enrollment count in the registry
        registry.decrementEnrollmentCount(_parameterGroup);

        emit CommunityUnenrolled(_community, _parameterGroup);
    }
    

    function getCommunityParameterGroups(string memory _community) external view returns (string[] memory) {
        return CommunityParameterGroups[_community];
    }

    function setCommunitiesContract(address _communitiesContract) external onlyOwner {
        require(_communitiesContract != address(0), "Invalid communities contract address");
        CommunitiesContract = CommunitiesInterface(_communitiesContract);
    }

    function setParameterGroupRegistryContract(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registry = ParameterGroupRegistry(_registryAddress);
    }
}
