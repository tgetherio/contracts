// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract tgetherParameterGroupRegistry {
    struct ParameterGroup {
        string name;
        address contractAddress;
        string encodedABI; // Base64 encoded ABI as a string
        string description;
        address owner;
        uint256 enrollmentCount; // Track the number of enrollments
        uint256 id;
    }

    mapping(string => ParameterGroup) public parameterGroupsByName; // Map name to ParameterGroup
    mapping(uint256 => string) public parameterGroupIds; // Map ID to name
    mapping(address => string) public parameterGroupNamesByAddress; // Map address to name

    string[] public parameterGroupNamesById;
    
    uint256 public parameterGroupCount;

    address public communityEnrollmentContract;
    address public owner;

    event ParameterGroupRegistered(
        string indexed name,
        address indexed contractAddress,
        address owner,
        string description,
        uint256 indexed id
    );

    event EnrollmentCountUpdated(string name, uint256 newCount);
    event ContractAddressUpdated(string name, address oldAddress, address newAddress);
    event OwnerUpdated(string name, address oldOwner, address newOwner);

    constructor() {
        owner = msg.sender;
        parameterGroupCount = 1; // Start counting from 1 for better readability
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    modifier onlyCommunityEnrollment() {
        require(msg.sender == communityEnrollmentContract, "Only CommunityEnrollment contract can perform this action");
        _;
    }

    function registerParameterGroup(
        string memory _name,
        address _contractAddress,
        string memory _encodedABI,
        string memory _description
    ) external {
        require(bytes(_name).length > 0, "Parameter group name cannot be empty");
        require(parameterGroupsByName[_name].contractAddress == address(0), "Parameter group already exists");
        require(bytes(parameterGroupNamesByAddress[_contractAddress]).length == 0, "Contract address already registered");

        // Increment the count before registering to use the correct ID
        uint256 newId = parameterGroupCount++;
        
        parameterGroupsByName[_name] = ParameterGroup({
            name: _name,
            contractAddress: _contractAddress,
            encodedABI: _encodedABI,
            description: _description,
            owner: msg.sender,
            enrollmentCount: 0,
            id: newId
        });

        parameterGroupNamesById.push(_name);
        parameterGroupIds[newId] = _name;
        parameterGroupNamesByAddress[_contractAddress] = _name;

        emit ParameterGroupRegistered(_name, _contractAddress, msg.sender, _description, newId);
    }

    function incrementEnrollmentCount(string memory _name) external onlyCommunityEnrollment {
        require(parameterGroupsByName[_name].contractAddress != address(0), "Parameter group does not exist");

        parameterGroupsByName[_name].enrollmentCount++;
        emit EnrollmentCountUpdated(_name, parameterGroupsByName[_name].enrollmentCount);
    }

    function decrementEnrollmentCount(string memory _name) external onlyCommunityEnrollment {
        require(parameterGroupsByName[_name].contractAddress != address(0), "Parameter group does not exist");
        require(parameterGroupsByName[_name].enrollmentCount > 0, "Enrollment count cannot be less than zero");

        parameterGroupsByName[_name].enrollmentCount--;
        emit EnrollmentCountUpdated(_name, parameterGroupsByName[_name].enrollmentCount);
    }

    function updateContractAddress(string memory _name, address _newAddress) external {
        ParameterGroup storage group = parameterGroupsByName[_name];
        require(group.contractAddress != address(0), "Parameter group does not exist");
        require(group.owner == msg.sender, "Only the owner can update the contract address");
        require(bytes(parameterGroupNamesByAddress[_newAddress]).length != 0, "Contract address already registered");

        address oldAddress = group.contractAddress;

        group.contractAddress = _newAddress;
        parameterGroupNamesByAddress[_newAddress] = _name;
        delete parameterGroupNamesByAddress[oldAddress];

        emit ContractAddressUpdated(_name, oldAddress, _newAddress);
    }

    function updateOwner(string memory _name, address _newOwner) external {
        ParameterGroup storage group = parameterGroupsByName[_name];
        require(group.contractAddress != address(0), "Parameter group does not exist");
        require(group.owner == msg.sender, "Only the owner can update ownership");

        address oldOwner = group.owner;
        group.owner = _newOwner;

        emit OwnerUpdated(_name, oldOwner, _newOwner);
    }

    function editParameterGroup(
        string memory _name,
        address _contractAddress,
        string memory _encodedABI,
        string memory _description
    ) external onlyOwner {
        require(parameterGroupsByName[_name].contractAddress != address(0), "Parameter group does not exist");
        require(parameterGroupsByName[_name].owner == msg.sender, "Only the owner can edit the parameter group");

        ParameterGroup storage group = parameterGroupsByName[_name];
        group.contractAddress = _contractAddress;
        group.encodedABI = _encodedABI;
        group.description = _description;

        emit ParameterGroupRegistered(_name, _contractAddress, group.owner, _description, group.id);
    }

    function getParameterGroupNamesPaginated(uint256 _amt, uint256 _pageNum) external view returns (string[] memory) {
        uint256 start = _amt * _pageNum;
        uint256 end = start + _amt;

        if (end > parameterGroupNamesById.length) {
            end = parameterGroupNamesById.length;
        }

        string[] memory names = new string[](end - start);

        for (uint256 i = start; i < end; i++) {
            names[i - start] = parameterGroupNamesById[i];
        }
        
        return names;
    }

    function getParameterGroupExists(string memory _name) external view returns (bool) {
        return parameterGroupsByName[_name].contractAddress != address(0);
    }

    function getParameterGroupByAddress(address _contractAddress) external view returns (ParameterGroup memory) {
        string memory name = parameterGroupNamesByAddress[_contractAddress];
        return parameterGroupsByName[name];
    }

    function setCommunityEnrollmentContract(address _address) external onlyOwner {
        communityEnrollmentContract = _address;
    }
}
