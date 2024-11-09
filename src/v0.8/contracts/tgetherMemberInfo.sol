// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract tgetherMembersInfo{

    struct Member {
        string name;
        string description;
        string[] degrees; 
        string[] awards;
        string endpoint; // can be aa link to X or wherever else needed
    }


    mapping(address => Member) public MembersInfo; // Use a mapping for easy access to members by address

    address private owner;

    constructor() {
        owner = msg.sender;
    }


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }


    // Events
    event MemberInfo(address indexed memberAddress ,string indexed name, string description, string[] degrees, string[] awards, string endpoint);

    // Functions

    /*

       * @notice Updates the information of a member.
       * @param _name Name of the member.
       * @param _description Description about the member.
       * @param _degrees List of degrees the member holds.
       * @param _awards List of awards the member has received.
        

    */

    function updateMemberInfo(string memory _name, string memory _description, string[] memory _degrees, string[] memory _awards, string memory _endpoint ) public {
        MembersInfo[msg.sender].name = _name;
        MembersInfo[msg.sender].description = _description;
        MembersInfo[msg.sender].degrees = _degrees;
        MembersInfo[msg.sender].awards = _awards;
        MembersInfo[msg.sender].endpoint = _endpoint;
        emit MemberInfo(msg.sender, _name, _description, _degrees, _awards, _endpoint);

    }


    function getMemberInfo(address _address)external view returns (string memory _name, string memory _description, string[] memory _degrees, string[] memory _awards, string memory _endpoint ){
        return(MembersInfo[_address].name,MembersInfo[_address].description,MembersInfo[_address].degrees, MembersInfo[_address].awards , MembersInfo[_address].endpoint );
    }

}