pragma solidity ^0.8.0;
import "hardhat/console.sol";

// This contract is just for testing functionality. It will not be used in the final version of the project. 
// CredAccessControl contracts are meant to allow communities to set their own parameters for 
// what they value in members. Examples could be number of reviews they make, number of posts they have had accepted
// number of submissions they have made, time spent in community, percent ownership of a particular asset etc. The point is YOU decide what is.


interface learntgetherMembersInterface{
    function contractSetCred(string memory _communityName,address _memberAddress, int256 _creds) external returns (int256);
    function inviteMember(string memory _communityName, address _memberAddress) external returns (address); 
    function uninviteMember(string memory _communityName, address _memberAddress) external returns (address); 

    }
contract MOCKCredAccess{
    learntgetherMembersInterface communityMemberaddress;
    string communityName;

    constructor(address _communityMemberaddress, string memory _communityName){
        communityMemberaddress = learntgetherMembersInterface(_communityMemberaddress);
        communityName = _communityName;
    }

    // This Type of function in most cases you want to only be internal or private.
    // You would use a check log/upkeep to confirm a change has been made needing a members cred to change
    // perform upkeep would then call this type of function to change the member's cred amount.
    function setMemberCred(address _memberAddress, int256 _creds) external returns (int256){
        int256 cred = communityMemberaddress.contractSetCred(communityName, _memberAddress, _creds);
        return cred;
    }
    function inviteMember(address _memberAddress) external returns (address){
      address ad = communityMemberaddress.inviteMember(communityName, _memberAddress); 
        return ad;
    }
    function uninviteMember(address _memberAddress) external returns (address){
      address ad = communityMemberaddress.uninviteMember(communityName, _memberAddress); 
        return ad;
    }


    function updateCommunity(string memory _communityName) external {
        communityName = _communityName;
    }

}