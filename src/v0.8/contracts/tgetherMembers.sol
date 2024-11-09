// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface tgetherCommuityInterface{
    function getCommunityExists(string memory _community) external view returns (bool);
    function getCommunityOwner(string memory _community) external view returns (address);
    function getCommunityIsInviteOnly(string memory _community) external view returns (bool);
    function getMemberAccessContract(string memory _community) external view returns (address);

}

contract tgetherMembers{


    struct communityInfo{
        int256 creds;
        mapping(address => int256) hasGivenCred;
        address[] postiveCredAddresses;
        address[] negativeCredAddresses;
        uint256 isMember;
    } 

    mapping(address => mapping(string => communityInfo)) membersMap; // Use a mapping for easy access to members by address

    mapping(address=> string[]) public memberCommunities; // Use a mapping for easy access to communities by address

    address private owner;

    tgetherCommuityInterface public communityContract;  // To be used when we need to port to v2
    constructor() {
        owner = msg.sender;
    }


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    mapping(string=> mapping(address => bool)) public isInvited; // Mapping to see if a user is invited to a community (only used for invitation based communities)



    modifier credRules(string memory _community, address _member){

        require(communityContract.getCommunityExists(_community), "Community Does Not Exist");
        
        // Ensure the community exsits 

        // Ensure the sender is a member for the community
        require(membersMap[msg.sender][_community].isMember != 0, "You are not a member.");
        
        // Ensure the target member exists of this community
        require(membersMap[_member][_community].isMember != 0, "Target member DNE");

        // Ensure a member is not editing creds to themselves
        require(msg.sender != _member, "You cannot edit own creds.");
        _;

    }

    // Events 
    
    event MemberInvited(string indexed communityName, address indexed memberAddress);
    event MemberUninvited(string indexed communityName, address indexed memberAddress);
    event MemberAdded(string indexed communityName, address indexed memberAddress);
    event MemberRemoved(string indexed communityName, address indexed memberAddress);
    event MemberInfo(address indexed memberAddress ,string indexed name, string description, string[] degrees, string[] awards );
    event AddedPosCred(string indexed communityName, address indexed memberAddress, address indexed actor ,int256 creds);
    event RemovedPosCred(string indexed communityName, address indexed memberAddress, address indexed actor ,int256 creds);
    event AddedNegCred(string indexed communityName, address indexed memberAddress, address indexed actor ,int256 creds);
    event RemovedNegCred(string indexed communityName, address indexed memberAddress, address indexed actor ,int256 creds);
    event IndexUpdated(string indexed communityName, address indexed memberAddress, address indexed actor, int256 index);
    event Creds(address indexed memberAddress, string indexed communityName, int256 creds, uint256 indexed timestamp);


    // Functions

    /*
        * @notice Invites a member to a given community.
        * @dev Ensures the community exists and the sender is the owner of the community.
        * @param _community Name of the community.
        * @param _member Address of the member.
    */
    function inviteMember(string memory _community, address _member) external returns (address){
        require(membersMap[_member][_community].isMember == 0, "Member already exists of this community.");
        require(isInvited[_community][_member] == false, "User Already Invited");
        address credAddress = communityContract.getMemberAccessContract(_community);
        require((msg.sender == communityContract.getCommunityOwner(_community) && credAddress == address(0))|| msg.sender == communityContract.getMemberAccessContract(_community)  , "You dont have permission invite Members");
        require(communityContract.getCommunityIsInviteOnly(_community)== true, "This community is not invite only.");

        // Adding them as invited but addresses(users) still have the option to accept in this.addselfasmember
        isInvited[_community][_member] = true;
        
        
        emit MemberInvited(_community, _member);

        return(_member);

    }
    /*
        * @notice Uninvites a member from a given community.
        * @dev Ensures the community exists and the sender is the owner of the community.
        * @param _community Name of the community.
        * @param _member Address of the member.
    */
    function uninviteMember(string memory _community, address _member) external returns (address){
        address credAddress = communityContract.getMemberAccessContract(_community);
        require((msg.sender == communityContract.getCommunityOwner(_community) && credAddress == address(0))|| msg.sender == communityContract.getMemberAccessContract(_community)  , "You dont have permission uninvite Members");        
        require(communityContract.getCommunityIsInviteOnly(_community)== true, "This community is not invite only.");
        require(isInvited[_community][_member] == true, "Member Not Invited");
        require(msg.sender != _member, "You cannot uninvite yourself.");

        isInvited[_community][_member] = false;

        // remove them as member if they already are one
        if (this.getIsMember(_member, _community) == true){
            membersMap[_member][_community].isMember= 0;
        }

        emit MemberUninvited(_community, _member);
        return(_member);

    }

        /*
            * @notice Adds the sender as a member for a given community.
            * @dev Ensures the community exists and the sender is not already a member.
            * @param _community Name of the community.
        */

    function addSelfAsMember(string memory _community) external  {

        require(communityContract.getCommunityExists(_community), "Community Does not Exist");
        require(membersMap[msg.sender][_community].isMember == 0, "You are already a member of this community.");

        // Ensure the user is invited if the community is invite only

        if (communityContract.getCommunityIsInviteOnly(_community)== true){

            require(isInvited[_community][msg.sender] == true, "You are not invited to this community.");
        }

        if (memberCommunities[msg.sender].length == 0){
            memberCommunities[msg.sender].push("");
        }
        
        memberCommunities[msg.sender].push(_community);

        membersMap[msg.sender][_community].isMember= memberCommunities[msg.sender].length -1;

        // Set first item to 0 to help mapping

        membersMap[msg.sender][_community].postiveCredAddresses.push(address(0));
        membersMap[msg.sender][_community].negativeCredAddresses.push(address(0));

        emit MemberAdded(_community, msg.sender);
    }

        /*

            * @notice Removes the sender as a member for a given community.
            * @dev Ensures the community exists and the sender is currently a member.
            * @param _community Name of the community.

        */
    function removeSelfAsMember(string memory _community) external  {

        require(communityContract.getCommunityExists(_community), "Community Does Not Exist");
        require(membersMap[msg.sender][_community].isMember != 0, "You are not a member of this community.");

        // swap pop our memberCommunities array
        uint256 index = uint256(membersMap[msg.sender][_community].isMember);
        if (index != memberCommunities[msg.sender].length -1) {
            // swap pop our memberCommunities array
            memberCommunities[msg.sender][index]= memberCommunities[msg.sender][memberCommunities[msg.sender].length -1];
            membersMap[msg.sender][memberCommunities[msg.sender][index]].isMember= index;

        }
            memberCommunities[msg.sender].pop();

            membersMap[msg.sender][_community].isMember= 0;


        membersMap[msg.sender][_community].isMember= 0;
        emit MemberRemoved(_community, msg.sender);
    }

    /*
        * @notice Adds creds to a member for a given commuinity.
        * @dev Ensures the community exists and the sender has the authority to add creds.
        * @param _community Name of the community.
        * @param _member Address of the member.
    */
    function addPosCredsToMember(string memory _community, address _member) external  credRules(_community, _member) {
        address credAddress = communityContract.getMemberAccessContract(_community);
        require(credAddress== address(0),  "Commmunity Uses a cred access contract");

        require(membersMap[_member][_community].hasGivenCred[msg.sender] == 0, "You've already given a cred to this member.");

        membersMap[_member][_community].creds += 1;
        emit Creds(_member, _community, membersMap[_member][_community].creds, block.timestamp);
        
        membersMap[_member][_community].postiveCredAddresses.push(msg.sender);
        membersMap[_member][_community].hasGivenCred[msg.sender] = int256(membersMap[_member][_community].postiveCredAddresses.length  -1);

        emit AddedPosCred(_community, _member, msg.sender, membersMap[_member][_community].creds);
    }


    function addNegCredsToMember(string memory _community, address _member) external  credRules(_community, _member) {
        address credAddress = communityContract.getMemberAccessContract(_community);
        require(credAddress== address(0),  "Commmunity Uses a cred access contract");

        require(membersMap[_member][_community].hasGivenCred[msg.sender] == 0, "You've already given a cred to this member.");

        membersMap[_member][_community].creds -= 1;
        emit Creds(_member, _community, membersMap[_member][_community].creds, block.timestamp);

        membersMap[_member][_community].negativeCredAddresses.push(msg.sender);
        membersMap[_member][_community].hasGivenCred[msg.sender] = int256(membersMap[_member][_community].negativeCredAddresses.length  -1) *-1;
        emit AddedNegCred(_community, _member, msg.sender, membersMap[_member][_community].creds);

    }


    // Internal function to handle the removal of creds, both positive and negative
    function _removeCred(
        string memory _community,
        address _member,
        bool isPositive
    ) internal {
        address credAddress = communityContract.getMemberAccessContract(_community);
        require(credAddress == address(0), "Community Uses a cred access contract");

        int256 givenCred = membersMap[_member][_community].hasGivenCred[msg.sender];
        require(
            (isPositive && givenCred > 0) || (!isPositive && givenCred < 0),
            isPositive ? "You have not given a positive cred to this member yet." : "Have not given a negative cred yet."
        );

         // Ensure arithmetic operations are consistently using int256
        membersMap[_member][_community].creds += isPositive ? int256(-1) : int256(1);
        emit Creds(_member, _community, membersMap[_member][_community].creds, block.timestamp);


        uint256 index = uint256(isPositive ? givenCred : givenCred * -1);
        address[] storage credAddresses = isPositive ? membersMap[_member][_community].postiveCredAddresses : membersMap[_member][_community].negativeCredAddresses;
    // Corrected type for index and ternary operation result
        if (index != credAddresses.length - 1) {
            credAddresses[index] = credAddresses[credAddresses.length - 1];
            // Ensure the multiplication result is also int256
            membersMap[_member][_community].hasGivenCred[credAddresses[index]] = int256(index) * (isPositive ? int256(1) : int256(-1));
            emit IndexUpdated(_community, _member, msg.sender, int256(index) * (isPositive ? int256(1) : int256(-1)));
        }

        membersMap[_member][_community].hasGivenCred[msg.sender] = 0;
        credAddresses.pop();

        if (isPositive) {
            emit RemovedPosCred(_community, _member, msg.sender, membersMap[_member][_community].creds);
        } else {
            emit RemovedNegCred(_community, _member, msg.sender, membersMap[_member][_community].creds);
        }
    }

    // Public function to remove positive creds, now simplified
    function removePosCredsFromMember(string memory _community, address _member) external credRules(_community, _member){
        _removeCred(_community, _member, true);
    }

    // Public function to remove negative creds, now simplified
    function removeNegCredsFromMember(string memory _community, address _member) external credRules(_community, _member){
        _removeCred(_community, _member, false);
    }

    function contractSetCred(string memory _community,address _member, int256 _creds) external returns (int256){
            address credAccess = communityContract.getMemberAccessContract(_community);
            require(msg.sender == credAccess && credAccess!= address(0) &&  membersMap[_member][_community].isMember != 0, "Not the cred access contract or User not member");
            membersMap[_member][_community].creds = _creds;
            return membersMap[_member][_community].creds;
        }







    // Getters

    function getIsInvited(address _member, string memory _community) external view returns (bool) {
        return isInvited[_community][_member];    }


    function getIsMember(address _member, string memory _community) external view returns (bool) {
        if (membersMap[_member][_community].isMember == 0){
            return false;
        } else{
            return true;
        }
    }

    function getMemberCreds(address _member, string memory _community) external view returns (int256 creds) {
        return membersMap[_member][_community].creds;
    }
    function getMemberPosCredsList(address _member, string memory _community)external view returns (address[] memory addressList){
        return membersMap[_member][_community].postiveCredAddresses;        
    }
    function getMemberNegCredsList(address _member, string memory _community)external view returns (address[] memory addressList){
        return membersMap[_member][_community].negativeCredAddresses;        
    }


    function getMemberCommunities(address _member) external view returns (string[] memory){
        return(memberCommunities[_member]);
    }

    function getMemberCredIndex(address _memberAddress, address _credGiverAddress, string memory _communityName)external view returns (int256 index){
        return membersMap[_memberAddress][_communityName].hasGivenCred[_credGiverAddress];        
    }
   

    function hasMemberGivenCred(address _member, string memory _community, address givenBy) external view returns (bool) {
        if (membersMap[_member][_community].hasGivenCred[givenBy]!= 0){
            return true;
        } else{
            return false;
        }
    }

    // Only Owner functions 

    function settgetherCommunities(address _contractAddress) external onlyOwner {
        communityContract= tgetherCommuityInterface(_contractAddress);

    
    }


}