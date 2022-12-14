pragma solidity^0.5.0;
import './Crypto.sol';

contract eVote {
    address public admin;
    bool public disputed;
    Crypto crypto;
    mapping(address=> uint[2]) public publicKeys;
    mapping(address=> uint[2]) public votes;
    mapping(address=>bool) public refunded;
    address[] public voters;
    uint[5] public endPhases;
    bytes32 public usersMerkleTreeRoot;
    bytes32 public computationMerkleTreeRoot;
    uint public finishRegistartionBlockNumber;
    uint public finishVotingBlockNumber;
    uint public finishTallyBlockNumber;
    uint public finishChallengeBlockNumber;
    uint public constant DEPOSIT = 1 ether;
    uint public voteCount;
    uint public voteResult;
    string public question;

    constructor(address _cryptoAddress, bytes32 _usersMerkleTreeRoot, string memory _question, uint[5] memory _endPhases) payable  public {
        require(msg.value==DEPOSIT,"Invalid deposit value");
        crypto = Crypto(_cryptoAddress);
        admin = msg.sender;
        usersMerkleTreeRoot = _usersMerkleTreeRoot;
        finishRegistartionBlockNumber = block.number + 100;
        finishVotingBlockNumber = finishRegistartionBlockNumber + 100;
        finishTallyBlockNumber = finishVotingBlockNumber + 100;
        finishChallengeBlockNumber = finishTallyBlockNumber + 100;
        question = _question;
        endPhases = _endPhases;
    }
    function registerVoter(uint[2] memory _pubKey, uint[3] memory _discreteLogProof, bytes32[] memory _merkleProof) public payable{
        require(msg.value==DEPOSIT,"Invalid deposit value");
        require(block.number<finishRegistartionBlockNumber,"Registration phase is already closed");
        require(crypto.verifyMerkleProof(_merkleProof, usersMerkleTreeRoot, keccak256(abi.encodePacked(msg.sender))), "Invalid Merkle proof");
        require(crypto.verifyDL(_pubKey, _discreteLogProof),"Invalid DL proof");
        publicKeys[msg.sender] = _pubKey;
        if(voters.length == 0) {
            voters.push(msg.sender);
        } else {
            for(uint i=0; i<voters.length; i++) {
                if(voters[i] != msg.sender && i == voters.length-1) {
                    voters.push(msg.sender);
                }
            }
        }
    }
    function castVote(uint[2] memory _vote, uint[2] memory _Y, uint[18] memory _zeroOrOneProof, uint _v) public {
        require(block.number >= finishRegistartionBlockNumber && block.number < finishVotingBlockNumber, "Voting phase is already closed");
        require(publicKeys[msg.sender] [0]!=0, "Unregistered voter");
        require(crypto.verifyZeroOrOne(_vote, _Y, _zeroOrOneProof),"Invalid zero or one proof");
        votes[msg.sender] = _vote;
        voteCount = ++voteCount;
        if(_v == 1) ++voteResult;
    }
    function setTallyResult(uint _result, bytes32 _computationRoot) public {
        require(msg.sender==admin,"Only admin can set the tally result");
        require(block.number >= finishVotingBlockNumber && block.number < finishTallyBlockNumber, "Tallying phase is already closed");
        voteResult = _result;
        computationMerkleTreeRoot = _computationRoot;
    }
    function disputeTallyResult(uint[3] memory t1, uint[3] memory t2, bytes32[] memory proof1,
     bytes32[] memory proof2) public {
        require(block.number >= finishTallyBlockNumber && block.number < finishChallengeBlockNumber, "Dispute phase is already closed");
        require(crypto.verifyMerkleProof(proof2, computationMerkleTreeRoot,
        keccak256(abi.encodePacked(t2))),"Invalid Merkle proof for t2");
        uint index = t2[0];
        if(index == 0) {
            //case 1
            uint[2] memory c1 = votes[voters[index]];
            disputed = !crypto.Equal(c1, [t2[1],t2[2]]);
        } else if (index == t1[0]+1) {
            //case 2
            require(crypto.verifyMerkleProof(proof1, computationMerkleTreeRoot,
            keccak256(abi.encodePacked(t1))),"Invalid Merkle proof for t1");
            uint[2] memory temp = crypto.ecAdd(votes[voters[index]],[t1[1],t1[2]]);
            disputed = !crypto.Equal(temp,[t2[1],t2[2]]);
        }
        else {
            //case 3
            disputed = !crypto.Equal(crypto.ecMul(voteResult),[t2[1],t2[2]]);
        }
        if(disputed) {
            voteResult = 0;
            msg.sender.transfer(DEPOSIT);
        }
    }
    function reclaimDeposit() public {
        require(block.number >= finishChallengeBlockNumber, "Invalid reclaim deposit phase");
        require(refunded[msg.sender] == false && (votes[msg.sender][0] != 0 || (!disputed && msg.sender == admin) ),"Illegal reclaim");
        refunded[msg.sender] = true;
        msg.sender.transfer(DEPOSIT);
    }
    function getQuestion() public view returns (string memory) {
        return question;
    }
    function getVoterCount() public view returns (uint){
        return voters.length;
    }
    function getVoteCount() public view returns (uint){
        return voteCount;
    }
    function getResult() public view returns (uint){
        return voteResult;
    }
    function getEndPhases() public view returns (uint[5] memory){
        return endPhases;
    }
}