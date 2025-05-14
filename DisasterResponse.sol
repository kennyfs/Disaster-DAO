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
        mapping(address => bool) hasVoted; // Replace this
        mapping(address => bool) voteType; // New: Records the vote type (true for approve, false for reject)
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
        mapping(address => bool) hasVoted; // Replace this
        mapping(address => bool) voteType; // New: Records the vote type (true for approve, false for reject)
    }

    struct DonationRecord {
        uint256 disasterId;
        string name;
        string donateAddress;
        string image_cid;
        uint256 total_amount;
        uint256[] dates;
        uint256 vote_per;
    }

    mapping(uint256 => Disaster) public disasters;
    mapping(uint256 => NewProposal) public newProposals;
    mapping(uint256 => ProofProposal) public proofProposals;
    mapping(uint256 => mapping(address => uint256)) public donations;
    mapping(uint256 => mapping(address => uint256)) public votingPower;
    mapping(address => bool) public admins; // New: Tracks admin addresses
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

    constructor(address[] memory initialAdmins) Ownable(msg.sender) {
        // 初始化合約，設定初始管理員
        disasterCount = 0;
        newProposalCount = 0;
        proofProposalCount = 0;

        // 設定初始管理員
        for (uint256 i = 0; i < initialAdmins.length; i++) {
            admins[initialAdmins[i]] = true;
        }
    }

    // 創建新的災難提案
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

    // 提交災難的請款證明
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

    // 管理員對新增災難提案進行投票
    function voteNew(uint256 newProposalId, bool approve) external {
        require(admins[msg.sender], "Only admins can vote"); // Restrict to admins
        NewProposal storage proposal = newProposals[newProposalId];
        require(
            block.timestamp <= proposal.votingDeadline,
            "Voting period ended"
        );
        require(!proposal.hasVoted[msg.sender], "Already voted");

        proposal.hasVoted[msg.sender] = true;
        proposal.voteType[msg.sender] = approve; // Record the vote type
        if (approve) {
            proposal.approveVotes += 1; // Admins have one vote each
        } else {
            proposal.rejectVotes += 1;
        }
        emit Voted(newProposalId, msg.sender, approve);
    }

    // 新增管理員（僅限合約擁有者）
    function addAdmin(address admin) external onlyOwner {
        admins[admin] = true;
    }

    // 移除管理員（僅限合約擁有者）
    function removeAdmin(address admin) external onlyOwner {
        admins[admin] = false;
    }

    // 對災難的請款提案進行投票
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
        proposal.voteType[msg.sender] = approve; // Record the vote type
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

    // 最終化災難提案，根據投票結果決定是否通過
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
            emit DisasterCreated(disasterCount);
        } else {
            payable(proposal.proposer).transfer((stakeAmount * 9) / 10);
        }
        proposal.approved = true;
    }

    // 最終化請款提案，根據投票結果決定是否通過
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

    // 捐款給指定的災難
    function donate(uint256 disasterId) external payable {
        require(msg.value > 0, "Donation must be greater than 0");
        require(disasters[disasterId].active, "Disaster not active");

        // Update donation and total donations
        donations[disasterId][msg.sender] += msg.value;
        disasters[disasterId].totalDonations += msg.value;

        // Calculate new voting power
        uint256 previousVotingPower = votingPower[disasterId][msg.sender];
        uint256 newVotingPower = sqrt(donations[disasterId][msg.sender] / 1e18);
        votingPower[disasterId][msg.sender] = newVotingPower;

        // Adjust votes if the donor has already voted for proof proposals
        for (uint256 i = 1; i <= proofProposalCount; i++) {
            if (
                proofProposals[i].disasterId == disasterId &&
                proofProposals[i].hasVoted[msg.sender]
            ) {
                if (proofProposals[i].voteType[msg.sender]) {
                    // Adjust approve votes
                    proofProposals[i].approveVotes =
                        proofProposals[i].approveVotes -
                        previousVotingPower +
                        newVotingPower;
                } else {
                    // Adjust reject votes
                    proofProposals[i].rejectVotes =
                        proofProposals[i].rejectVotes -
                        previousVotingPower +
                        newVotingPower;
                }
            }
        }

        emit Donated(disasterId, msg.sender, msg.value, newVotingPower);
    }

    // 獲取災難總數
    function getDisasterCount() external view returns (uint256) {
        return disasterCount;
    }

    // 獲取所有災難的列表
    function getDisasterList() external view returns (Disaster[] memory) {
        Disaster[] memory disasterList = new Disaster[](disasterCount);
        for (uint256 i = 1; i <= disasterCount; i++) {
            disasterList[i - 1] = disasters[i];
        }
        return disasterList;
    }

    // 根據災難 ID 獲取災難詳情
    function getDisasterById(
        uint256 disasterId
    ) external view returns (Disaster memory) {
        return disasters[disasterId];
    }

    // 獲取用戶可以投票的災難 ID 列表
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

    // 獲取用戶可以投票的新增災難提案
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

    // 獲取指定災難的可投票請款提案
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

    // 獲取指定新增災難提案的詳情
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

    // 獲取指定請款提案的詳情
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

    // 獲取用戶的捐款總數
    function getMyDonationsCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i <= disasterCount; i++) {
            if (donations[i][msg.sender] > 0) {
                count++;
            }
        }
        return count;
    }

    // 獲取用戶的捐款記錄
    function getMyDonations(uint256 from, uint256 to) external view returns (DonationRecord[] memory) {
        require(from < to, "Invalid range");
        require(to <= disasterCount, "Range exceeds disaster count");

        // First count valid donations in range
        uint256 count = 0;
        for (uint256 i = from; i < to; i++) {
            if (donations[i][msg.sender] > 0) {
                count++;
            }
        }

        DonationRecord[] memory records = new DonationRecord[](count);
        uint256 index = 0;

        // Fill records array
        for (uint256 i = from; i < to; i++) {
            if (donations[i][msg.sender] > 0) {
                uint256[] memory datesArray = new uint256[](1);
                datesArray[0] = block.timestamp; // Just using current time as example

                records[index] = DonationRecord({
                    disasterId: i,
                    name: disasters[i].name,
                    donateAddress: address(this).toString(),
                    image_cid: disasters[i].photoCid,
                    total_amount: donations[i][msg.sender],
                    dates: datesArray,
                    vote_per: votingPower[i][msg.sender]
                });
                index++;
            }
        }
        return records;
    }

    // 獲取已到期的災難 ID 列表
    function dueDisaster() external view returns (uint256[] memory) {
        uint256[] memory dueDisasters = new uint256[](disasterCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= disasterCount; i++) {
            if (block.timestamp > disasters[i].deadline) {
                dueDisasters[count] = i;
                count++;
            }
        }
        
        // Create correctly sized array
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = dueDisasters[i];
        }
        return result;
    }

    // 獲取正在進行中的災難 ID 列表
    function ongoingDisaster() external view returns (uint256[] memory) {
        uint256[] memory activeDisasters = new uint256[](disasterCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= disasterCount; i++) {
            if (block.timestamp <= disasters[i].deadline && disasters[i].active) {
                activeDisasters[count] = i;
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeDisasters[i];
        }
        return result;
    }

    // 獲取用戶未投票的請款提案 ID 列表
    function unvoteProposal(uint256 disasterId) external view returns (uint256[] memory) {
        uint256[] memory unvotedProposals = new uint256[](proofProposalCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= proofProposalCount; i++) {
            if (proofProposals[i].disasterId == disasterId && 
                !proofProposals[i].hasVoted[msg.sender] &&
                block.timestamp <= proofProposals[i].votingDeadline) {
                unvotedProposals[count] = i;
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = unvotedProposals[i];
        }
        return result;
    }

    // 獲取用戶已投票的請款提案 ID 列表
    function voteProposal(uint256 disasterId) external view returns (uint256[] memory) {
        uint256[] memory votedProposals = new uint256[](proofProposalCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= proofProposalCount; i++) {
            if (proofProposals[i].disasterId == disasterId && 
                proofProposals[i].hasVoted[msg.sender]) {
                votedProposals[count] = i;
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = votedProposals[i];
        }
        return result;
    }

    // 獲取正在進行中的請款提案 ID 列表
    function ongoingProposal(uint256 disasterId) external view returns (uint256[] memory) {
        uint256[] memory ongoingProposals = new uint256[](proofProposalCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= proofProposalCount; i++) {
            if (proofProposals[i].disasterId == disasterId && 
                !proofProposals[i].approved &&
                block.timestamp <= proofProposals[i].votingDeadline) {
                ongoingProposals[count] = i;
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ongoingProposals[i];
        }
        return result;
    }

    // 獲取指定請款提案的詳細資訊
    function getProposalDetails(uint256 proposalId) external view returns (
        uint256 id,
        string memory title,
        address creator,
        uint256 startedDate,
        uint256 dueDate,
        bool canFinalize,
        string memory previewCID,
        string memory zipCID,
        uint256 total_avail_count,
        uint256 support_count,
        uint256 reject_count
    ) {
        ProofProposal storage proposal = proofProposals[proposalId];
        
        return (
            proposal.id,
            proposal.title,
            proposal.proposer,
            proposal.votingDeadline - VOTING_PERIOD, // startedDate
            proposal.votingDeadline,
            !proposal.approved && block.timestamp > proposal.votingDeadline,
            proposal.cid, // previewCID 
            proposal.cid, // zipCID (in this case we use same CID)
            votingPower[proposal.disasterId][msg.sender],
            proposal.approveVotes,
            proposal.rejectVotes
        );
    }

    // 將地址轉換為字串
    function toString(address account) internal pure returns (string memory) {
        return toHexString(uint256(uint160(account)), 20);
    }

    // 將數值轉換為十六進制字串
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes16 _SYMBOLS = "0123456789abcdef";
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }

    // 計算平方根
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
