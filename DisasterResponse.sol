// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DisasterResponse is Ownable, ReentrancyGuard {
    struct Disaster {
        string name;
        string photoCid; // 代表性的災難照片
        string cid; // 標題以外的敘述都傳到 IPFS，避免儲存太多資料花費太多 Gas Fee（如果網頁不想做這麼麻煩，也可以直接存成字串）
        uint256 deadline; // 可以固定為開始日期起 6 個月之類的，方便實作
        uint256 totalDonations;
        bool active;
    }

    struct NewProposal {
        uint256 id;
        string title;
        string cid; // 標題以外的敘述都傳到 IPFS，避免儲存太多資料花費太多 Gas Fee（如果網頁不想做這麼麻煩，也可以直接存成字串）
        address proposer;
        bool approved;
        uint256 approveVotes;
        uint256 rejectVotes;
        uint256 votingDeadline;
        mapping(address => bool) hasVoted;
    }

    struct ProofProposal {
        uint256 id;
        uint256 disasterId;
        string title;
        string cid;
        uint256 amount;
        address proposer;
        bool approved;
        uint256 approveVotes;
        uint256 rejectVotes;
        uint256 votingDeadline;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => Disaster) public disasters;
    mapping(uint256 => NewProposal) public newProposals;
    mapping(uint256 => ProofProposal) public proofProposals;
    mapping(uint256 => mapping(address => uint256)) public donations;
    mapping(uint256 => mapping(address => uint256)) public votingPower;
    mapping(address => uint256) public globalVotingPower;
    uint256 public disasterCount;
    uint256 public inactiveDisasterCount; // 因此 ID 為 inactiveDisasterCount+1 ~ disasterCount 的災難才是活躍災難
    // 要如何把災難設為不活躍？一樣做一個函數給人呼叫並給予獎勵？有沒有其他辦法？
    uint256 public newProposalCount;
    uint256 public proofProposalCount;
    uint256 public stakeAmount = 0.1 ether;
    uint256 public newRewardAmount = 0.005 ether;
    uint256 public finalizeRewardAmount = 0.001 ether;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant MIN_APPROVE_RATIO_NEW = 5; // 新增災難同意票需達總票數 5%，因為先前的捐款者可能沒有活躍關注此 DAO。
    uint256 public constant MIN_APPROVE_RATIO_PROOF = 25; // 請款同意票需達總票數 1/4

    event DisasterProposed(
        uint256 indexed proposalId,
        address proposer,
        string title,
        uint256 deadline
    );
    event ProofProposed(
        uint256 indexed proposalId,
        uint256 disasterId,
        address proposer,
        string title
    );
    event Voted(uint256 indexed proposalId, address voter, bool approve);
    event DisasterCreated(uint256 indexed disasterId);
    event ProofApproved(
        uint256 indexed proposalId
    );
    event Donated(
        uint256 indexed disasterId,
        address indexed donor,
        uint256 amount,
        uint256 votingPower
    );

    constructor() Ownable(msg.sender) {
        disasterCount = 0;
        newProposalCount = 0;
        proofProposalCount = 0;
    }

    function createDisaster(
        string memory title,
        string memory cid,
        uint256 deadline
    ) external payable {
        require(msg.value == stakeAmount, "Must stake 0.1 ETH");
        newProposalCount++;
        NewProposal storage proposal = newProposals[newProposalCount];
        proposal.id = newProposalCount;
        proposal.title = title;
        proposal.cid = cid;
        proposal.proposer = msg.sender;
        proposal.approved = false;
        proposal.votingDeadline = block.timestamp + VOTING_PERIOD;
        emit DisasterProposed(newProposalCount, msg.sender, title, deadline);
    }

    function submitProof(
        uint256 disasterId,
        string memory title,
        string memory cid,
        uint256 amount
    ) external {
        require(disasters[disasterId].active, "Disaster not active");
        proofProposalCount++;
        ProofProposal storage proposal = proofProposals[proofProposalCount];
        proposal.id = proofProposalCount;
        proposal.disasterId = disasterId;
        proposal.title = title;
        proposal.cid = cid;
        proposal.amount = amount;
        proposal.proposer = msg.sender;
        proposal.approved = false;
        proposal.votingDeadline = block.timestamp + VOTING_PERIOD;
        emit ProofProposed(proofProposalCount, disasterId, msg.sender, title);
    }

    function voteNew(uint256 newProposalId, bool approve) external {
        NewProposal storage proposal = newProposals[newProposalId];
        require(
            block.timestamp <= proposal.votingDeadline,
            "Voting period ended"
        );
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(globalVotingPower[msg.sender] > 0, "No global voting power");
        proposal.hasVoted[msg.sender] = true;
        if (approve) {
            proposal.approveVotes += globalVotingPower[msg.sender];
        } else {
            proposal.rejectVotes += globalVotingPower[msg.sender];
        }
        emit Voted(newProposalId, msg.sender, approve);
    }

    function voteProof(uint256 proofProposalId, bool approve) external {
        ProofProposal storage proposal = proofProposals[proofProposalId];
        require(
            block.timestamp <= proposal.votingDeadline,
            "Voting period ended"
        );
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(
            votingPower[proposal.disasterId][msg.sender] > 0,
            "No voting power for this disaster"
        );
        proposal.hasVoted[msg.sender] = true;
        if (approve) {
            proposal.approveVotes += votingPower[proposal.disasterId][
                msg.sender
            ];
        } else {
            proposal.rejectVotes += votingPower[proposal.disasterId][
                msg.sender
            ];
        }
        emit Voted(proofProposalId, msg.sender, approve);
    }

    function finalizeDisaster(uint256 proposalId) external nonReentrant {
        NewProposal storage proposal = newProposals[proposalId];
        require(
            block.timestamp > proposal.votingDeadline,
            "Voting period not ended"
        );
        require(!proposal.approved, "Already finalized");
        uint256 totalVotes = proposal.approveVotes + proposal.rejectVotes;
        bool passed = proposal.approveVotes > proposal.rejectVotes &&
            totalVotes > 0 &&
            (proposal.approveVotes * 100) / totalVotes >= MIN_APPROVE_RATIO_NEW;
        if (passed) {
            disasterCount++;
            disasters[disasterCount] = Disaster(
                proposal.title,
                proposal.cid,
                block.timestamp + 30 days, // 假設災難持續 30 天
                0,
                true
            );
            payable(proposal.proposer).transfer(stakeAmount + newRewardAmount);
            emit DisasterCreated(disasterCount,);
        } else {
            payable(proposal.proposer).transfer((stakeAmount * 9) / 10);
        }
        proposal.approved = true;
    }

    function approveProof(uint256 proposalId) external nonReentrant {
        ProofProposal storage proposal = proofProposals[proposalId];
        require(
            block.timestamp > proposal.votingDeadline,
            "Voting period not ended"
        );
        require(!proposal.approved, "Already approved");
        uint256 totalVotes = proposal.approveVotes + proposal.rejectVotes;
        bool passed = proposal.approveVotes > proposal.rejectVotes &&
            (proposal.approveVotes * 100) / totalVotes >= MIN_APPROVE_RATIO_PROOF;
        require(passed, "Not enough votes");
        uint256 amount = proposal.amount;
        require(address(this).balance >= amount, "Insufficient funds");
        payable(proposal.proposer).transfer(amount);
        proposal.approved = true;
        emit ProofApproved(
            proposalId
        );
    }

    function donate(uint256 disasterId) external payable {
        require(msg.value > 0, "Donation must be greater than 0");
        require(disasters[disasterId].active, "Disaster not active");
        donations[disasterId][msg.sender] += msg.value;
        disasters[disasterId].totalDonations += msg.value;
        uint256 newVotingPower = sqrt(donations[disasterId][msg.sender] / 1e18);
        votingPower[disasterId][msg.sender] = newVotingPower;
        globalVotingPower[msg.sender] += newVotingPower;
        emit Donated(disasterId, msg.sender, msg.value, newVotingPower);
    }

    function getDisasterCount() external view returns (uint256) {
        return disasterCount;
    }

    function getDisasterList() external view returns (Disaster[] memory) {
        Disaster[] memory disasterList = new Disaster[](disasterCount);
        for (uint256 i = 1; i <= disasterCount; i++) {
            disasterList[i - 1] = disasters[i];
        }
        return disasterList;
    }

    function getDisasterById(
        uint256 disasterId
    ) external view returns (Disaster memory) {
        return disasters[disasterId];
    }

    function canVoteDisaster(
        address voter
    ) external view returns (uint256[] memory) {
        uint256[] memory votableDisasters = new uint256[](disasterCount);
        uint256 count = 0;
        for (uint256 i = 1; i <= disasterCount; i++) {
            if (votingPower[i][voter] > 0) {
                votableDisasters[count] = i;
                count++;
            }
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = votableDisasters[i];
        }
        return result;
    }

    function getVoteableNewProposals()
        external
        view
        returns (NewProposal[] memory)
    {
        NewProposal[] memory votableProposals = new NewProposal[](
            newProposalCount
        );
        uint256 count = 0;
        for (uint256 i = 1; i <= newProposalCount; i++) {
            if (
                !newProposals[i].approved &&
                block.timestamp <= newProposals[i].votingDeadline
            ) {
                votableProposals[count] = newProposals[i];
                count++;
            }
        }
        NewProposal[] memory result = new NewProposal[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = votableProposals[i];
        }
        return result;
    }

    function getVoteableProofProposals(
        uint256 disasterId
    ) external view returns (ProofProposal[] memory) {
        ProofProposal[] memory votableProposals = new ProofProposal[](
            proofProposalCount
        );
        uint256 count = 0;
        for (uint256 i = 1; i <= proofProposalCount; i++) {
            if (
                proofProposals[i].disasterId == disasterId &&
                !proofProposals[i].approved &&
                block.timestamp <= proofProposals[i].votingDeadline
            ) {
                votableProposals[count] = proofProposals[i];
                count++;
            }
        }
        ProofProposal[] memory result = new ProofProposal[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = votableProposals[i];
        }
        return result;
    }

    function getNewProposal(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 id,
            string memory title,
            string memory cid,
            address proposer,
            bool approved,
            uint256 approveVotes,
            uint256 rejectVotes,
            uint256 votingDeadline
        )
    {
        NewProposal storage proposal = newProposals[proposalId];
        return (
            proposal.id,
            proposal.title,
            proposal.cid,
            proposal.proposer,
            proposal.approved,
            proposal.approveVotes,
            proposal.rejectVotes,
            proposal.votingDeadline
        );
    }

    function getProofProposal(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 id,
            uint256 disasterId,
            string memory title,
            string memory cid,
            uint256 amount,
            address proposer,
            bool approved,
            uint256 approveVotes,
            uint256 rejectVotes,
            uint256 votingDeadline
        )
    {
        ProofProposal storage proposal = proofProposals[proposalId];
        return (
            proposal.id,
            proposal.disasterId,
            proposal.title,
            proposal.cid,
            proposal.amount,
            proposal.proposer,
            proposal.approved,
            proposal.approveVotes,
            proposal.rejectVotes,
            proposal.votingDeadline
        );
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
