// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract tgetherPosts is ERC721Enumerable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    struct Post {
        string content;
        string title;
        address authorAddress;
        string authorName;
        string description;
    }
    mapping(uint256 => Post) public posts;

    constructor() ERC721("LearntgetherPosts", "LTG") {
        _tokenIdCounter.increment();
    }
event PostMintedTo(uint256 indexed postId, address indexed authorAddress, string authorName);

function mintPost(
    string memory _content,
    string memory _title,
    string memory _authorName,
    string memory _description
) public returns (uint256) {
    uint256 newTokenId = _tokenIdCounter.current();

    Post memory newPost = Post({
        content: _content,
        title: _title,
        authorAddress: msg.sender,
        authorName: _authorName,
        description: _description
    });

    _safeMint(msg.sender, newTokenId);
    _tokenIdCounter.increment();

    // Save post data in the mapping
    posts[newTokenId] = newPost;

    // Emit the event with the correct arguments
    emit PostMintedTo(newTokenId, msg.sender, _authorName);
    return newTokenId;
}


    // Generate a base64-encoded tokenURI dynamically
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        Post memory post = posts[tokenId];
        
        // Create metadata JSON object
        string memory json = string(
            abi.encodePacked(
                '{"name":"', post.title, '",',
                '"description":"', post.description, '",',
                '"content":"', post.content, '"}'
            )
        );

        // Base64 encode the JSON object and return it as a data URI
        string memory jsonBase64 = Base64.encode(bytes(json));
        return string(abi.encodePacked("data:application/json;base64,", jsonBase64));
    }
}
