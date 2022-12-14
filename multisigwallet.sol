// SPDX-License-Identifier: RamboFURY

pragma solidity 0.8.7; //default version of solidity selected as in remix ide

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

contract MultiSig {

    address mainOwner;
    address[] walletOwners; //array to append the wallet owners
    uint limit;
    uint depositId = 0;
    uint withdrawalId = 0;
    uint transferId =0;
    string[] tokenList;
    address multisigInstance;

    constructor() {

        mainOwner = msg.sender; //contract creator
        walletOwners.push(mainOwner); //the deployer is pushed to owners array at first 
        limit = walletOwners.length - 1;
        tokenList.push("ETH");
    }

    //key-value pairs
    mapping(address=>mapping(string=>uint)) balance;
    mapping(address=>mapping(uint=>bool)) approvals;
    mapping(string=>Token) tokenMapping;

    struct Token {

        string symbol;
        address tokenAddress;

    }

    struct Transfer {
        string symbol;
        address sender;
        address payable receiver;
        uint amount;
        uint id;
        uint approvals;
        uint timeOfTransaction;

    }

    Transfer[] transferRequests;//array to store transfer requests and to query them when needed

    // logs of transactions
    event walletOwnerAdded(address addedBy, address ownerAdded,uint timeOfTransaction);
    event walletOwnerRemoved(address removedBy, address ownerRemoved,uint timeOfTransaction);
    event fundsDeposited(string symbol,address sender, uint amount,uint depositid, uint timeOfTransaction);
    event fundsWithdrawed(string symbol,address sender, uint amount,uint withdrawlid, uint timeOfTransaction);
    event transferCreated(string symbol,address sender,address receiver,uint amount,uint transferid,uint approvals,uint timeOfTransaction);
    event transferCancelled(string symbol,address sender,address receiver,uint amount,uint transferid,uint approvals,uint timeOfTransaction);
    event transferApproved(string symbol,address sender,address receiver,uint amount,uint transferid,uint approvals,uint timeOfTransaction);
    event fundsTransferred(string symbol,address sender,address receiver,uint amount,uint transferid,uint approvals,uint timeOfTransaction);
    event tokenAdded(address addedBy,string symbol,address tokenAddress, uint timeOfTransaction);

    modifier onlyOwners() { //modifier is used to reduce recurring code snippets

        bool isOwner=false;
        for(uint i=0; i<walletOwners.length; i++){ //#1 security issue - only existing owners should call this function not anyone from outside
            if(walletOwners[i]==msg.sender){
                isOwner=true;
                break;
            }
        }

        require(isOwner==true,"Only wallet owners can call this function.");
        _;
    }

    modifier tokenExists(string memory symbol) {

        require(tokenMapping[symbol].tokenAddress != address(0),"Token does not exists.");
        _;

    }

    function addToken(string memory symbol,address _tokenAddress) public onlyOwners {

        for(uint i=0; i<tokenList.length; i++) {

            require(keccak256(bytes(tokenList[i]))!=keccak256(bytes(symbol)),"Cannot add a duplicate token.");
        }
        
        require(keccak256(bytes(ERC20(_tokenAddress).symbol()))==keccak256(bytes(symbol)));

        tokenMapping[symbol]=Token(symbol,_tokenAddress);

        tokenList.push(symbol);

        emit tokenAdded(msg.sender,symbol,_tokenAddress,block.timestamp);
    }

    function setMultisigContractaddress(address walletAddress) private {

        multisigInstance=walletAddress;

    }

    function callAddOwner(address owner,address multiSigContractInstance) private {

        MultiSigFactory factory=MultiSigFactory(multisigInstance);
        factory.addNewWalletInstance(owner,multiSigContractInstance);

    }

    function callremoveOwner(address owner,address multiSigContractInstance) private {

        MultiSigFactory factory=MultiSigFactory(multisigInstance);
        factory.removeNewWalletInstance(owner,multiSigContractInstance);

    }

    function addWalletOwner(address owner,address walletAddress,address _address) public onlyOwners {

        for(uint i=0; i<walletOwners.length; i++) //#2 security issue - remove duplicacy of owners
        {
            if(walletOwners[i]==owner){
                revert("Cannot add duplicate owners.");
            }

        }

        walletOwners.push(owner); //to add a new owner
        limit = walletOwners.length - 1;

        emit walletOwnerAdded(msg.sender,owner,block.timestamp);
        setMultisigContractaddress(walletAddress);
        callAddOwner(owner,_address);
    }

    function removeWalletOwner(address owner,address walletAddress,address _address) public onlyOwners {
        
        bool hasBeenFound=false;
        uint ownerIndex;
        for(uint i=0; i<walletOwners.length; i++){
            if(walletOwners[i]==owner){
                hasBeenFound=true;
                ownerIndex=i;
                break;
            }
        }

        require(hasBeenFound==true,"Wallet owner not detected.");
        walletOwners[ownerIndex] = walletOwners[walletOwners.length-1];
        walletOwners.pop(); //solidity allows deletion in an array by moving the element to the last index and then remove
        limit=walletOwners.length-1;
        emit walletOwnerRemoved(msg.sender,owner,block.timestamp);

        setMultisigContractaddress(walletAddress);
        callremoveOwner(owner,_address);
    }

    function deposit(string memory symbol,uint amount) public payable onlyOwners tokenExists(symbol) {

        require(balance[msg.sender][symbol]>=0,"Can not deposit a value 0 or less."); //depositable ethereum function as well as ERC 20

        if(keccak256(bytes(symbol))==keccak256(bytes("ETH"))) {
        
        balance[msg.sender]["ETH"]=msg.value;
    }  

    else {

        require(tokenMapping[symbol].tokenAddress != address(0),"Token does not exists.");
        balance[msg.sender][symbol]+=amount;
        IERC20(tokenMapping[symbol].tokenAddress).transferFrom(msg.sender,address(this),amount);

    }
       emit fundsDeposited("ETH",msg.sender,msg.value,depositId,block.timestamp);
       depositId++;
        
    }

    function withdraw(string memory symbol,uint amount) public onlyOwners {

        require(balance[msg.sender][symbol]>=amount);
        balance[msg.sender][symbol]-=amount;

        if(keccak256(bytes(symbol))==keccak256(bytes("ETH"))) { //to check if we are dealing with ether

        payable(msg.sender).transfer(amount); //if not ether this occurs
      
    } 
    
    else {

        require(tokenMapping[symbol].tokenAddress != address(0),"Token does not exists.");
        IERC20(tokenMapping[symbol].tokenAddress).transfer(msg.sender,amount);
    }
        
        emit fundsWithdrawed(symbol,msg.sender,amount,withdrawalId,block.timestamp);
        withdrawalId++;

    } 

    function createTransferRequest(string memory symbol,address payable receiver, uint amount) public onlyOwners {

    require(balance[msg.sender][symbol]>=amount,"Insufficient funds.");
    for(uint i=0; i<walletOwners.length; i++){

        require(walletOwners[i] != receiver, "Cannot transfer funds within the wallet.");//#3 security issue - avoid sending funds to ourself

    }
    
    balance[msg.sender][symbol]-=amount;
    transferRequests.push(Transfer(symbol,msg.sender,receiver,amount,transferId,0,block.timestamp));
    transferId++;
    emit transferCreated(symbol,msg.sender,receiver,amount,transferId,0,block.timestamp);

    }

    function cancelTransferRequest(string memory symbol,uint id) public onlyOwners {

        string memory symbol=transferRequests[id].symbol;
        bool hasBeenFound=false;
        uint transferIndex=0;
        for(uint i=0; i<transferRequests.length; i++){

            if(transferRequests[i].id==id){

                hasBeenFound=true;
                break;
            }

            transferIndex++;
        }

        require(hasBeenFound,"Transfer id not found.");
        require(msg.sender==transferRequests[transferIndex].sender);

        balance[msg.sender][symbol]+=transferRequests[transferIndex].amount;
        transferRequests[transferIndex]=transferRequests[transferRequests.length-1];

        emit transferCancelled(symbol,msg.sender,transferRequests[transferIndex].receiver,transferRequests[transferIndex].amount,transferRequests[transferIndex].id,transferRequests[transferIndex].approvals,transferRequests[transferIndex].timeOfTransaction);
        transferRequests.pop();

    }

    function approveTransferRequest(string memory symbol,uint id) public onlyOwners {

        string memory symbol=transferRequests[id].symbol;
        bool hasBeenFound=false;
        uint transferIndex=0;
        for(uint i=0; i<transferRequests.length-1; i++){

            if(transferRequests[i].id==id){

                hasBeenFound=true;
                break;
            }

            transferIndex++;

        }

        require(hasBeenFound);
        require(transferRequests[transferIndex].receiver==msg.sender,"Cannot approve your own transfer.");  //#4 security check so that sender does not send to itself
        require(approvals[msg.sender][id]==false,"Cannot approve twice.");

        transferRequests[transferIndex].approvals +=1;
        approvals[msg.sender][id]=true;

        emit transferApproved(symbol,msg.sender,transferRequests[transferIndex].receiver,transferRequests[transferIndex].amount,transferRequests[transferIndex].id,transferRequests[transferIndex].approvals,transferRequests[transferIndex].timeOfTransaction);


        if(transferRequests[transferIndex].approvals==limit){

            transferFunds(symbol,transferIndex);
        }
    }

    function transferFunds(string memory symbol,uint id) private {

        balance[transferRequests[id].receiver][symbol]+=transferRequests[id].amount;
        if(keccak256(bytes(symbol))==keccak256(bytes("ETH"))) {

            transferRequests[id].receiver.transfer(transferRequests[id].amount);

        }

        else {

            IERC20(tokenMapping[symbol].tokenAddress).transfer(transferRequests[id].receiver,transferRequests[id].amount);
           
        }
        
        emit fundsTransferred(symbol,msg.sender,transferRequests[id].receiver,transferRequests[id].amount,transferRequests[id].id,transferRequests[id].approvals,transferRequests[id].timeOfTransaction);
        
        transferRequests[id]=transferRequests[transferRequests.length-1];
        transferRequests.pop();

    }

    function getWalletOwners() public view returns(address[] memory) { //view keyword makes the function read only
    
    return walletOwners;

    }

    function getApprovals(uint id) public view returns(bool) {

        return approvals[msg.sender][id];

    }

    function getTransferRequests() public view returns(Transfer[] memory) {

        return transferRequests;

    }

    function getBalance(string memory symbol) public view returns(uint) {

        return balance[msg.sender][symbol];
    }

    function getApprovalLimit() public view returns (uint) {

        return limit;

    }

    function getContractETHBalance() public view returns(uint) {

        return address(this).balance;
    } 

    function getTokenList() public view returns(string[] memory) {
        
        return tokenList;

    }

    function getContractERC20Balance(string memory symbol) public view tokenExists(symbol) returns(uint) {
        
        return balance[address(this)][symbol];

    }

}

    contract MultiSigFactory {
    
    struct UserWallets{
        
        address walletAddress;

    }
    
    UserWallets[] userWallets;
    MultiSig[] multisigWalletIntances;
    
    mapping(address => UserWallets[]) ownersWallets;
    
    event WalletCreated(address createdBy, address newWalletContractAddress, uint timeOfTransaction);
    
    
    function createNewWallet() public {
        
        MultiSig newMultisigWalletContract = new MultiSig();
        multisigWalletIntances.push(newMultisigWalletContract);
        
        UserWallets[] storage newWallet = ownersWallets[msg.sender];
        newWallet.push(UserWallets(address(newMultisigWalletContract)));
        
        emit WalletCreated(msg.sender, address(newMultisigWalletContract), block.timestamp);

    }
    
    
    function addNewWalletInstance(address owner, address walletAddress) public {
        
        UserWallets[] storage newWallet = ownersWallets[owner];
        newWallet.push(UserWallets(walletAddress));
        
    }
    
    function removeNewWalletInstance(address _owner, address _walletAddress) public {
        
        UserWallets[] storage newWallet = ownersWallets[_owner];
        
        bool hasBeenFound = false;
        uint walletIndex;
        for (uint i = 0; i < newWallet.length; i++) {
            
            if(newWallet[i].walletAddress == _walletAddress) {
                
                hasBeenFound = true;
                walletIndex = i;
                break;

            }
            
        }
        
        require(hasBeenFound, "the owners does not own the wallet specified");
        
        newWallet[walletIndex] = newWallet[newWallet.length - 1];
        newWallet.pop();
        
       }
    
    function getOwnerWallets(address owner) public view returns(UserWallets[] memory) {
        
        return ownersWallets[owner];

    }
    
}