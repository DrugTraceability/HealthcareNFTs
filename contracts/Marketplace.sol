// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol"; //Inherit the NFT ERC721 standard smart contract from openzeppelin

import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; //Reentracy protection for the smart contract

import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract Marketplace is ReentrancyGuard {

    using ECDSA for bytes32;


    // Variables
    
    uint public DeliveryDuration; //The allowed time to delivery the item after inititing redemption
    uint public RedemptionPeriod; // The allowed time for buyers to redeem before the seller can claim the NFT value
    address payable public immutable MarketplaceOwner; // the account that receives fees from sales, immutable means they can be assigned a value once
    address public arbitrator; //The arbitrator makes the final decision in case of a disput
    uint public immutable feePercent; // the fee percentage on sales 
    uint public itemCount;
    //mapping(address => uint) public securityDeposit; //A mapping that tracks the amount of security deposit within the marketplace smart contract
    
    struct Item {
        uint itemId; //This is used within the marketplace only
        IERC721 nft; //Creates an interface with nft smart contract
        uint tokenId; //This ID is specific for each NFT within the nft smart contract itself
        uint price;
        uint SellingTime;
        uint DeliveryStartTime;
        address payable seller;
        address redeemer; //This address is used for signature verification during redemption process
        bool sold;
        //bool valueClaimed; //This shows if the seller has collected the value of the NFT after the redemption period is over or after a successful delivery
        bool redeemed; //This shows if the NFT has already been redeemed for its real counterpart (Successfully redeemed)
        bool disputed;
        NFTState NFTstate; //Indicates the current delivery stage of the NFT
    }

    //Mapping the item number to the struct
    mapping(uint => Item) public items;


    //Disputes
    //struct DisputeDetails{}


    //Signatures
    struct Signature{
        address redeemer;
        uint itemId;
        IERC721 nft;
        uint tokenId;
        string message;
        bytes sig;
    }
    mapping(uint => Signature) public signatures;
    //mapping(uint => uint) public DeliveryStartTime; //This mapping is used to store the start of delivery time for each nft
    //mapping(uint => uint) public SellingTime; //This mapping is used to store the selling time of each NFT
    mapping(uint => bool) public valueClaimed; //This shows if the seller has collected the value of the NFT after the redemption period is over or after a successful delivery
                                              // Adding it to the struct directly causes the following error CompilerError: Stack too deep when compiling inline assembly: Variable value0 is 1 slot(s) too deep inside the stack.

    //The IPFS URI of the openned and challenged disputes
    mapping(uint => string) public opennedDisputeIPFS; 
    mapping(uint => string) public challengedDisputeIPFS; 

    //Enumerate variable for the delivery state of the NFT
    enum NFTState {Listed, Purchased, RedeemInitiated, EnRoute, Delivered, Disputed, Challenged}
    enum DisputeDecision {DeniedReceiving, RejectReceiving, DamagedItem, NotDelivered}
    DisputeDecision public Disputedecision;
    //NFTDeliveryState public DeliveryState;

    event Offered(uint itemId, address indexed nft, uint tokenId, uint price, address indexed seller);
    event Bought(uint itemId, address indexed nft, uint tokenId, uint price, address indexed seller, address indexed buyer);
    event RedemptionRequest(uint itemID, address indexed nft, uint tokenId, address indexed buyer, uint redemptiontime);
    event DeliveryStarted(address indexed Seller, address indexed nft, uint tokenId, address indexed buyer, uint deliverytime);
    event DeliveryProof(address indexed Seller, address indexed nft, uint tokenId, address indexed buyer, uint deliverytime);
    event DisputeOpenned(address indexed Seller, address indexed nft, address indexed Buyer, uint tokenId, bytes32 IPFShash);
    event DisputeSettlement(address indexed Seller, address indexed nft, address indexed Buyer, uint tokenId, DisputeDecision _decision);
    event SignatureStorage(address indexed verifiedAddress, address indexed redeemer, address indexed nft, uint tokenId, string message, bytes signature);
    event DisputeChallenged(address indexed Seller, address indexed nft, address indexed Buyer, uint tokenId, bytes32 IPFShash);


    constructor(uint _feePercent, uint _DeliveryDuration, uint _RedemptionPeriod) {
        DeliveryDuration = _DeliveryDuration * 1 days;
        RedemptionPeriod = _RedemptionPeriod * 1 days;
        MarketplaceOwner = payable(msg.sender);
        arbitrator = 0xb5Ee4B7b2366425c71ABd97096079550CF4dF218;
        feePercent = _feePercent; //The marketplace receives a percentage of all sales
    }

    //Checks the balance of the smart contract
    function getBalance() public view returns (uint256) {
    return address(this).balance;
    }

    //Get the EOA of arbitrator
    function getArbitratorAddress() public view returns (address) {
    return arbitrator;
    }
    
    // Make item to offer on the marketplace
    function makeItem(IERC721 _nft, uint _tokenId, uint _price) external payable nonReentrant { //IERC721 _nft takes the address of the nft and make it an nft instance, nonReentrant is from the imported reentrancyguard 
        require(_price > 0, "Price must be greater than zero");
        // increment itemCount
        itemCount ++;
        // transfer nft
        _nft.transferFrom(msg.sender, address(this), _tokenId); //moves the nft to the smartcontract
        // add new item to items mapping
        items[itemCount] = Item (itemCount, _nft, _tokenId, _price, 99999999999, 99999999999,  payable(msg.sender), address(0), false, false, false, NFTState.Listed);
        // emit Offered event 
        emit Offered(itemCount, address(_nft), _tokenId, _price, msg.sender); //The nft address is fetched by casting it in the address operator
    }


    function purchaseItem(uint _itemId) external payable nonReentrant { //external to prevent accessing it from within the smart contract
        uint _totalPrice = getTotalPrice(_itemId);
        Item storage item = items[_itemId]; //Storage is used to declare that it is reading directly from the mapping (not creating a memory copy)
        require(_itemId > 0 && _itemId <= itemCount, "item doesn't exist");
        require(msg.value >= _totalPrice, "not enough ether to cover item price and market fee");
        require(!item.sold, "item already sold");
        require(msg.sender != item.seller, "The item seller cannot purchase his/her own item");
        // pay seller and feeAccount
        //item.seller.transfer(item.price);
        //payable(address(this)).transfer(item.price); //The price of the item is kept in the smart contract for the allowed period for redemption
        payable(address(this)).call{value: item.price};
        MarketplaceOwner.transfer(_totalPrice - item.price); //This is the first transfer of ether from the buyer to the SC
        // update item to sold
        item.sold = true;
        // transfer nft to buyer
        item.nft.transferFrom(address(this), msg.sender, item.tokenId);
        item.NFTstate = NFTState.Purchased;
        item.SellingTime = block.timestamp; //Stores the selling time of the NFT by using the _itemID which is used within the marketplace only
        // emit Bought event
        emit Bought(_itemId, address(item.nft), item.tokenId, item.price, item.seller, msg.sender);
    }

    function getTotalPrice(uint _itemId) view public returns(uint){ //view because it only views variables without modifying them
        return((items[_itemId].price*(100 + feePercent))/100);
        //return((items[_itemId].price));
    }

    function ClaimNFTValue(uint _itemCount) public{
        Item storage item = items[_itemCount];
        require(msg.sender == item.seller, "Only the seller of this NFT can claim its value");
        require(!valueClaimed[item.itemId],"The value of the NFT has already been claimed");
        require(block.timestamp > item.SellingTime + RedemptionPeriod || item.NFTstate == NFTState.Delivered, "The value of the NFT can only be claimed if the redemption period is over");
        require(!item.disputed, "If there is a dispute, the value of the NFT will be handled by the arbitrator");
        payable(msg.sender).transfer(item.price); 
        //item.valueClaimed = true;
        valueClaimed[item.itemId] = true;

    }

    function RedeemNFT(uint _itemCount) external payable {  
    Item storage item = items[_itemCount];
    require(msg.sender == item.nft.ownerOf(item.tokenId), "Only the current owner of the NFT is allowed to redeem it");
    //require(items[_itemCount].tokenId == _tokenId, "The inserted itemcount doesn't belong to the same tokenID");
    require(!item.redeemed, "This NFT has already been successfully redeemed");
    
    item.redeemer = msg.sender;
    item.DeliveryStartTime = block.timestamp; //Store Delivery start time. This is the start of the timer for the seller to deliver
    item.NFTstate = NFTState.RedeemInitiated;
    item.nft.transferFrom(msg.sender, address(this), item.tokenId); 
    //payable(address(this)).transfer(item.price); //This is the second transfer of ether from the buyer to the SC
    payable(address(this)).call{value: item.price}; //This is the second transfer of ether from the buyer to the SC

    emit RedemptionRequest (_itemCount, address(item.nft), item.tokenId , msg.sender, block.timestamp);

    }

    function startDelivery(uint _itemCount) public{
        Item storage item = items[_itemCount];
        require(msg.sender == item.seller, "Only the NFT seller can initiate the delivery process"); //Assuming that the seller is responsible for delivering the item to the buyer
        require(item.NFTstate == NFTState.RedeemInitiated, "The buyer should initiate NFT redemption first or the delivery process has already started");
        require(block.timestamp < item.DeliveryStartTime + DeliveryDuration , "Can't start delivery after the specified delivery duration");

        item.NFTstate = NFTState.EnRoute;

        emit DeliveryStarted(msg.sender, address(item.nft), item.tokenId, item.nft.ownerOf(item.tokenId), block.timestamp);

    }

    //This function can only be executed if the buyer signs the reception message off-chain and the seller stores it on-chain using recoverSigner function 
    function ProofofDelivery(uint _itemCount) public{
        Item storage item = items[_itemCount];
        Signature storage signature = signatures[_itemCount];
        //require(isValidSignature(signature.message, signature.sig, signature.itemId), "Invalid signature");
        require(msg.sender == item.seller, "Only the NFT seller is allowed to execute this function");
        require(item.NFTstate == NFTState.EnRoute, "Cannot run this function as the item is still not out for delivery");
        require(block.timestamp < item.DeliveryStartTime + DeliveryDuration , "Can't end delivery after the specified delivery duration");
        require(signature.redeemer == item.redeemer, "The seller cannot prove delivery without the signature of the buyer");
        
        item.NFTstate = NFTState.Delivered; //The seller declares delivering the NFT
        item.redeemed = true; //The NFT is redeemed successfully

        emit DeliveryProof(msg.sender, address(item.nft), item.tokenId,  item.nft.ownerOf(item.tokenId),  block.timestamp);

    }



    //This function is used when either the buyer or seller wants to open a dispute
    function OpenDispute(uint _itemCount, string memory _IPFShash) public {
        Item storage item = items[_itemCount];
        require(msg.sender == item.redeemer, "Only the redeemer of the NFT can execute this function");
        require(item.NFTstate != NFTState.Delivered, "Cannot open a dispute if the item has already been delivered successfully");
        require(block.timestamp <= item.SellingTime + RedemptionPeriod, "Cannot open a dispute if the redemption period is over");

        //item.NFTstate = NFTState.Disputed;
        item.disputed = true;
        item.NFTstate = NFTState.Disputed;
        opennedDisputeIPFS[item.tokenId] = _IPFShash;

        emit DisputeOpenned(item.seller, address(item.nft), item.nft.ownerOf(item.tokenId), item.tokenId, bytes32(bytes(_IPFShash)));

        

    }
        //This function is used when either the buyer or seller wants to open a dispute
    function ChallengeDispute(uint _itemCount, string memory _IPFShash) public{
        Item storage item = items[_itemCount];
        require(msg.sender == item.seller, "Only the seller of the item can execute this function");
        require(item.NFTstate != NFTState.Delivered, "Cannot open a dispute if the item has already been delivered successfully");
        require(block.timestamp <= item.SellingTime + RedemptionPeriod, "Cannot open a dispute if the redemption period is over");
        require(item.disputed, "Only disputed items can be challenged");
        require(item.NFTstate != NFTState.Challenged, "This dispute has already been challenged");

        item.NFTstate = NFTState.Challenged;
        challengedDisputeIPFS[item.tokenId] = _IPFShash;


        emit DisputeChallenged(item.seller, address(item.nft), item.nft.ownerOf(item.tokenId), item.tokenId, bytes32(bytes(_IPFShash)));

    }

        function getopenneddisputeIPFS(uint _itemId) view public returns(string memory){ //view because it only views variables without modifying them
        return(opennedDisputeIPFS[_itemId]);
        //return((items[_itemId].price));
    }

        function getchallengeddisputeIPFS(uint _itemId) view public returns(string memory){ //view because it only views variables without modifying them
        return(challengedDisputeIPFS[_itemId]);
        //return((items[_itemId].price));
    }

    //This function is used to make the final decision in case of a dispute
    function DisputeFinalDecision(uint _itemCount, address _winner, DisputeDecision _decision) public{
        Item storage item = items[_itemCount];
        require(msg.sender == arbitrator, "Only the arbitrator is allowed to run this function and settle a dispute");
        require(_winner == item.seller || _winner == item.redeemer, "The winner must either be the buyer or the seller");
        require(item.disputed, "The item has not been disputed");

        if(_winner == item.seller && _decision == DisputeDecision.DeniedReceiving){ //This means the buyer received the item but denied it
        
            payable(_winner).transfer(2*item.price); //The seller gets twice the value of the NFT
            item.nft.transferFrom(address(this), address(0) , item.tokenId); //The nft is burned as it is already received by the buyer

        } 
        
        if(_winner == item.seller && _decision == DisputeDecision.RejectReceiving){ //This means the seller tried delivering but the buyer rejected

            payable(_winner).transfer(2*item.price); //The seller gets twice the value of the item
            item.nft.transferFrom(address(this), _winner , item.tokenId); //The nft is transferred backed to the seller
            item.redeemer = address(0); //The redeemer address is reset
            item.sold = false; //The NFT can be listed again by the seller
            item.redeemed = false; //Should be false anyway
        }

        if(_winner == item.redeemer && _decision == DisputeDecision.DamagedItem){
            payable(_winner).transfer(2*item.price); //The buyer gets twice the value of the item
        }

        if(_winner == item.redeemer && _decision == DisputeDecision.NotDelivered){
            
            payable(_winner).transfer(2*item.price); //The buyer gets twice the value of the item
            item.nft.transferFrom(address(this), address(0) , item.tokenId); //The nft is burned because the seller failed to deliver it

        }

        emit DisputeSettlement(_winner, address(item.nft), item.redeemer, item.tokenId, _decision);

        
    }

    //Storing the signature of the buyer
    function storeSignatures(string memory message, uint8 v, bytes32 r, bytes32 s, bytes memory sig, uint _itemCount) public {
        Item storage item = items[_itemCount];
        require(isValidSignature(message, v, r, s) == item.redeemer, "Invalid signature");
        require(msg.sender == item.seller, "Only the seller of the item can store signatures");

        signatures[_itemCount] = Signature (item.redeemer, item.itemId, item.nft, item.tokenId, message, sig);

        emit SignatureStorage(isValidSignature(message, v, r, s), item.redeemer, address(item.nft), item.tokenId, message, sig);

    }

// Returns the address that signed a given string message
  function isValidSignature(string memory message, uint8 v, bytes32 r, bytes32 s) public pure returns (address signer) {
    // The message header; we will fill in the length next
    string memory header = "\x19Ethereum Signed Message:\n000000";
    uint256 lengthOffset;
    uint256 length;
    assembly {
      // The first word of a string is its length
      length := mload(message)
      // The beginning of the base-10 message length in the prefix
      lengthOffset := add(header, 57)
    }
    // Maximum length we support
    require(length <= 999999);
    // The length of the message's length in base-10
    uint256 lengthLength = 0;
    // The divisor to get the next left-most message length digit
    uint256 divisor = 100000;
    // Move one digit of the message length to the right at a time
    while (divisor != 0) {
      // The place value at the divisor
      uint256 digit = length / divisor;
      if (digit == 0) {
        // Skip leading zeros
        if (lengthLength == 0) {
          divisor /= 10;
          continue;
        }
      }
      // Found a non-zero digit or non-leading zero digit
      lengthLength++;
      // Remove this digit from the message length's current value
      length -= digit * divisor;
      // Shift our base-10 divisor over
      divisor /= 10;
      
      // Convert the digit to its ASCII representation (man ascii)
      digit += 0x30;
      // Move to the next character and write the digit
      lengthOffset++;
      assembly {
        mstore8(lengthOffset, digit)
      }
    }
    // The null string requires exactly 1 zero (unskip 1 leading 0)
    if (lengthLength == 0) {
      lengthLength = 1 + 0x19 + 1;
    } else {
      lengthLength += 1 + 0x19;
    }
    // Truncate the tailing zeros from the header
    assembly {
      mstore(header, lengthLength)
    }
    // Perform the elliptic curve recover operation
    bytes32 check = keccak256(abi.encodePacked(header, message));
    return ecrecover(check, v, r, s); 
  }



}


