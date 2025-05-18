// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DisasterResponse is Ownable, ReentrancyGuard {
    // ====== Structs ======
    struct Disaster {
        string name;
        string photoCid; // 代表性的災難照片
        string description;
        uint256 deadline; // 可以固定為開始日期起 6 個月之類的，方便實作
        uint256 balance;
        uint256 totalVotes; // 新增：每個災難的總投票權
        address residualAddress;
    }

    struct Request {
        // 新建災難
        uint256 id;
        string title;
        string photoCid;
        string description;
        address proposer;
        bool approved;
        uint256 approveVotes;
        uint256 rejectVotes;
        uint256 votingDeadline;
        address residualAddress;
        // mapping(address => bool) hasVoted; // Replace this
        // mapping(address => bool) voteType; // New: Records the vote type (true for approve, false for reject)
    }

    struct Proposal {
        // 請款
        uint256 id;
        uint256 disasterId;
        string title;
        string photoCid;
        string description;
        string proofCid;
        uint256 amount;
        address proposer;
        bool approved;
        uint256 approveVotes;
        uint256 rejectVotes;
        uint256 votingDeadline;
        uint256 timeLock;
        // mapping(address => bool) hasVoted; // moved out
        // mapping(address => bool) voteType; // moved out
    }

    struct DonationRecord {
        uint256 disasterId;
        string name;
        uint256 total_amount;
        uint256 vote_per;
    }

    // ====== Storage ======
    mapping(uint256 => Disaster) public disasters;
    mapping(uint256 => Request) public requests;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => uint256)) public donations;
    mapping(uint256 => mapping(address => uint256)) public votingPower;
    mapping(address => bool) public admins; // New: Tracks admin addresses
    address[] public adminList; // 新增：admin array
    uint256 public disasterCount;
    // uint256 public inactiveDisasterCount; // 刪除：未使用
    // 要如何把災難設為不活躍？一樣做一個函數給人呼叫並給予獎勵？有沒有其他辦法？
    uint256 public requestCount;
    uint256 public proposalCount;
    uint256 public stakeAmount = 0.1 ether;
    uint256 public newRewardAmount = 0.005 ether;
    // uint256 public finalizeRewardAmount = 0.001 ether; // 刪除：未使用
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant TIMELOCK = 1 days;
    uint256 public constant MIN_APPROVE_RATIO_NEW = 5; // 新增災難同意票需達總票數 5%，因為先前的捐款者可能沒有活躍關注此 DAO。
    uint256 public constant MIN_APPROVE_RATIO_PROOF = 25; // 請款同意票需達總票數 1/4
    uint256 public constant VOTING_POWER_BASE = 1e6; // 新增：投票權基準單位
    uint256 public constant DEFAULT_DISASTER_DURATION = 180 days; // 新增：預設災難持續天數

    // ====== Voting Mappings ======
    mapping(uint256 => mapping(address => bool)) public requestHasVoted;
    mapping(uint256 => mapping(address => bool)) public requestVoteType;
    mapping(uint256 => mapping(address => bool)) public proposalHasVoted;
    mapping(uint256 => mapping(address => bool)) public proposalVoteType;

    // ====== Events ======
    event DisasterRequested(
        uint256 indexed requestId,
        address proposer,
        string title,
        uint256 deadline
    );
    event ProposalProposed(
        uint256 indexed proposalId,
        uint256 disasterId,
        address proposer,
        string title
    );
    event DisasterVoted(uint256 indexed requestId, address voter, bool approve);
    event ProposalVoted(
        uint256 indexed proposalId,
        address voter,
        bool approve
    );
    event DisasterCreated(uint256 indexed disasterId);
    event ProposalApproved(uint256 indexed proposalId);
    event Donated(
        uint256 indexed disasterId,
        address indexed donor,
        uint256 amount,
        uint256 votingPower
    );

    // ====== Constructor ======
    constructor(address[] memory initialAdmins) Ownable(msg.sender) {
        // 初始化合約，設定初始管理員
        disasterCount = 0;
        requestCount = 0;
        proposalCount = 0;

        // 設定初始管理員
        for (uint256 i = 0; i < initialAdmins.length; i++) {
            address admin = initialAdmins[i];
            if (!admins[admin]) {
                admins[admin] = true;
                adminList.push(admin);
            }
        }

        // 自動將合約部署者設為管理員
        if (!admins[msg.sender]) {
            admins[msg.sender] = true;
            adminList.push(msg.sender);
        }
    }

    // ====== Admin Functions ======
    function addAdmin(address admin) external onlyOwner {
        if (!admins[admin]) {
            admins[admin] = true;
            adminList.push(admin);
        }
    }

    // 移除管理員（僅限合約擁有者）
    function removeAdmin(address admin) external onlyOwner {
        if (admins[admin]) {
            admins[admin] = false;
            // 從 adminList 移除
            for (uint256 i = 0; i < adminList.length; i++) {
                if (adminList[i] == admin) {
                    adminList[i] = adminList[adminList.length - 1];
                    adminList.pop();
                    break;
                }
            }
        }
    }

    // 計算 admin 數量
    function getAdminCount() public view returns (uint256) {
        return adminList.length;
    }

    // ====== Disaster Request Functions ======
    // 創建新的災難請求
    function addRequest(
        string memory title,
        string memory photoCid,
        string memory description,
        uint256 deadline,
        address residualAddress
    ) external payable {
        require(msg.value == stakeAmount, "Must stake 0.1 ETH");
        requestCount++;
        Request storage request = requests[requestCount];
        request.id = requestCount;
        request.title = title;
        request.photoCid = photoCid;
        request.description = description;
        request.proposer = msg.sender;
        request.approved = false;
        request.approveVotes = 0;
        request.rejectVotes = 0;
        request.votingDeadline = block.timestamp + VOTING_PERIOD;
        request.residualAddress = residualAddress;
        emit DisasterRequested(requestCount, msg.sender, title, deadline);
    }

    // 管理員對災難請求進行投票
    function voteRequest(uint256 requestId, bool approve) external {
        require(admins[msg.sender], "Only admins can vote"); // Restrict to admins
        Request storage request = requests[requestId];
        require(
            block.timestamp <= request.votingDeadline,
            "Voting period ended"
        );
        require(!requestHasVoted[requestId][msg.sender], "Already voted");

        requestHasVoted[requestId][msg.sender] = true;
        requestVoteType[requestId][msg.sender] = approve; // Record the vote type
        if (approve) {
            request.approveVotes += 1; // Admins have one vote each
        } else {
            request.rejectVotes += 1;
        }
        emit DisasterVoted(requestId, msg.sender, approve);
    }

    // 最終化災難請求，根據投票結果決定是否通過
    function finalizeDisaster(uint256 requestId) external nonReentrant {
        Request storage request = requests[requestId];
        require(admins[msg.sender], "Only admins can finalize a disaster."); // Restrict to admins
        // 由於是管理員投票並最終化，不需 timeLock
        require(!request.approved, "Already finalized");
        // 以 admin 數量作為總票數
        uint256 totalVotes = getAdminCount();
        bool passed = request.approveVotes > request.rejectVotes &&
            totalVotes > 0 &&
            (request.approveVotes * 100) / totalVotes >= MIN_APPROVE_RATIO_NEW;
        if (passed) {
            disasterCount++;
            disasters[disasterCount] = Disaster(
                request.title,
                request.photoCid,
                request.description,
                block.timestamp + DEFAULT_DISASTER_DURATION, // 假設災難持續 180 天
                0,
                0,
                request.residualAddress
            );
            uint256 returnAmount = (address(this).balance <
                stakeAmount + newRewardAmount)
                ? address(this).balance
                : stakeAmount + newRewardAmount;
            // min(整個合約的餘額, 該發出去的錢)
            payable(request.proposer).transfer(returnAmount);
            emit DisasterCreated(disasterCount);
        } else {
            uint256 returnAmount = (address(this).balance <
                (stakeAmount * 9) / 10)
                ? address(this).balance
                : (stakeAmount * 9) / 10;
            // 還是檢查一下，以防真的不夠發。
            payable(request.proposer).transfer(returnAmount);
        }
        request.approved = true;
    }

    // ====== Proposal Functions ======
    // 提交災難的請款證明
    function submitProposal(
        uint256 disasterId,
        string memory title,
        uint256 amount,
        string memory description,
        string memory photoCid,
        string memory proofCid
    ) external {
        require(
            block.timestamp <= disasters[disasterId].deadline,
            "Disaster not active"
        );
        proposalCount++;
        Proposal storage proposal = proposals[proposalCount];
        proposal.id = proposalCount;
        proposal.disasterId = disasterId;
        proposal.title = title;
        proposal.photoCid = photoCid;
        proposal.description = description;
        proposal.proofCid = proofCid;
        proposal.amount = amount;
        proposal.proposer = msg.sender;
        proposal.approved = false;
        proposal.approveVotes = 0;
        proposal.rejectVotes = 0;
        proposal.votingDeadline = block.timestamp + VOTING_PERIOD;
        proposal.timeLock = block.timestamp + TIMELOCK;

        emit ProposalProposed(proposalCount, disasterId, msg.sender, title);
    }

    // 對災難的請款提案進行投票
    function voteProposal(uint256 proposalId, bool approve) external {
        Proposal storage proposal = proposals[proposalId];
        require(
            block.timestamp <= proposal.votingDeadline,
            "Voting period ended"
        );
        require(!proposalHasVoted[proposalId][msg.sender], "Already voted");
        require(
            votingPower[proposal.disasterId][msg.sender] > 0,
            "No voting power for this disaster"
        );
        proposalHasVoted[proposalId][msg.sender] = true;
        proposalVoteType[proposalId][msg.sender] = approve; // Record the vote type
        if (approve) {
            proposal.approveVotes += votingPower[proposal.disasterId][
                msg.sender
            ];
        } else {
            proposal.rejectVotes += votingPower[proposal.disasterId][
                msg.sender
            ];
        }
        emit ProposalVoted(proposalId, msg.sender, approve);
    }

    // 最終化請款提案，根據投票結果決定是否通過
    function finalizeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.timeLock, "Timelock not reached.");
        require(!proposal.approved, "Already approved");
        uint256 totalVotes = disasters[proposal.disasterId].totalVotes;
        bool passed = proposal.approveVotes > proposal.rejectVotes &&
            totalVotes > 0 &&
            (proposal.approveVotes * 100) / totalVotes >=
            MIN_APPROVE_RATIO_PROOF;
        require(passed, "Not enough votes");
        uint256 amount = proposal.amount;
        require(
            address(this).balance >= amount &&
                disasters[proposal.disasterId].balance >= amount,
            "Insufficient funds"
        );
        // 確保整個合約的錢夠發，且該災難的錢也夠發。有可能因為發出 newRewardAmount 導致災難的錢夠發，但合約的錢不夠發。
        // 若因為餘額不足而失敗，請款人再發一個 Proposal 即可。
        // 任何交易的 Gas fee 都由交易發起人負擔，而不是合約負擔，因此只要合約餘額足夠就可以了。
        payable(proposal.proposer).transfer(amount);
        disasters[proposal.disasterId].balance -= amount;
        proposal.approved = true;
        emit ProposalApproved(proposalId);
    }

    // ====== Donation Functions ======
    // 捐款給指定的災難
    function donate(uint256 disasterId) external payable {
        require(msg.value > 0, "Donation must be greater than 0");
        require(
            block.timestamp <= disasters[disasterId].deadline,
            "Disaster not active"
        );

        // Update donation and total donations
        donations[disasterId][msg.sender] += msg.value;
        disasters[disasterId].balance += msg.value;

        // Calculate new voting power
        uint256 previousVotingPower = votingPower[disasterId][msg.sender];
        uint256 newVotingPower = sqrt(
            donations[disasterId][msg.sender] / VOTING_POWER_BASE
        );
        votingPower[disasterId][msg.sender] = newVotingPower;

        // 只會增加投票權
        disasters[disasterId].totalVotes += (newVotingPower -
            previousVotingPower);

        // 調整已投票提案的 approve/reject votes
        adjustProposalVotes(
            disasterId,
            msg.sender,
            previousVotingPower,
            newVotingPower
        );

        emit Donated(disasterId, msg.sender, msg.value, newVotingPower);
    }

    // 調整已投票提案的 approve/reject votes
    function adjustProposalVotes(
        uint256 disasterId,
        address voter,
        uint256 previousVotingPower,
        uint256 newVotingPower
    ) internal {
        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].disasterId == disasterId &&
                proposalHasVoted[i][voter]
            ) {
                if (proposalVoteType[i][voter]) {
                    proposals[i].approveVotes =
                        proposals[i].approveVotes -
                        previousVotingPower +
                        newVotingPower;
                } else {
                    proposals[i].rejectVotes =
                        proposals[i].rejectVotes -
                        previousVotingPower +
                        newVotingPower;
                }
            }
        }
    }

    // ====== Disaster End ======
    function endDisaster(uint256 disasterId) external {
        // 若過期，把錢全部給指定的地址
        require(
            block.timestamp > disasters[disasterId].deadline,
            "Disaster not ended"
        );

        address residualAddress = disasters[disasterId].residualAddress;
        uint256 remainingBalance = (address(this).balance >
            disasters[disasterId].balance)
            ? disasters[disasterId].balance
            : address(this).balance;
        // 剩餘資金 = min(整個合約的餘額, 該災難的餘額)

        // 將剩餘的資金轉移到指定地址
        payable(residualAddress).transfer(remainingBalance);
        disasters[disasterId].balance = 0;
    }

    // ====== View Functions ======
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
    function getVotableDisaster(
        address voter
    ) external view returns (uint256[] memory) {
        uint256[] memory votableDisasters = new uint256[](disasterCount);
        uint256 count = 0;
        for (uint256 i = 1; i <= disasterCount; i++) {
            if (
                votingPower[i][voter] > 0 &&
                block.timestamp <= disasters[i].deadline
            ) {
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

    // 獲取用戶可以投票的災難請求
    function getVotableRequests() external view returns (Request[] memory) {
        Request[] memory votableRequests = new Request[](requestCount);
        uint256 count = 0;
        for (uint256 i = 1; i <= requestCount; i++) {
            if (
                !requests[i].approved &&
                block.timestamp <= requests[i].votingDeadline
            ) {
                votableRequests[count] = requests[i];
                count++;
            }
        }
        Request[] memory result = new Request[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = votableRequests[i];
        }
        return result;
    }

    // 獲取指定災難的可投票請款提案
    function getVotableProposals(
        uint256 disasterId
    ) external view returns (Proposal[] memory) {
        Proposal[] memory votableProposals = new Proposal[](proposalCount);
        uint256 count = 0;
        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].disasterId == disasterId &&
                !proposals[i].approved &&
                block.timestamp <= proposals[i].votingDeadline &&
                block.timestamp <= disasters[disasterId].deadline
            ) {
                votableProposals[count] = proposals[i];
                count++;
            }
        }
        Proposal[] memory result = new Proposal[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = votableProposals[i];
        }
        return result;
    }

    // 獲取指定新增災難請求的詳情
    function getNewRequest(
        uint256 requestId
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
        Request storage request = requests[requestId];
        return (
            request.id,
            request.title,
            request.photoCid,
            request.proposer,
            request.approved,
            request.approveVotes,
            request.rejectVotes,
            request.votingDeadline
        );
    }

    // 獲取指定請款提案的詳情
    function getProposal(
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
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.disasterId,
            proposal.title,
            proposal.photoCid,
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
    function getMyDonations(
        uint256 from,
        uint256 to
    ) external view returns (DonationRecord[] memory) {
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
                records[index] = DonationRecord({
                    disasterId: i,
                    name: disasters[i].name,
                    total_amount: donations[i][msg.sender],
                    vote_per: votingPower[i][msg.sender]
                });
                index++;
            }
        }
        return records;
    }

    // 獲取已到期的災難 ID 列表
    function getDueDisaster() external view returns (uint256[] memory) {
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
    function getOngoingDisaster() external view returns (uint256[] memory) {
        uint256[] memory activeDisasters = new uint256[](disasterCount);
        uint256 count = 0;

        for (uint256 i = 1; i <= disasterCount; i++) {
            if (block.timestamp <= disasters[i].deadline) {
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
    function getUnvoteProposal(
        uint256 disasterId
    ) external view returns (uint256[] memory) {
        uint256[] memory unvotedProposals = new uint256[](proposalCount);
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].disasterId == disasterId &&
                !proposalHasVoted[i][msg.sender] && // <-- use mapping, not struct member
                block.timestamp <= proposals[i].votingDeadline
            ) {
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
    function getVotedProposal(
        uint256 disasterId
    ) external view returns (uint256[] memory) {
        uint256[] memory votedProposals = new uint256[](proposalCount);
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].disasterId == disasterId &&
                proposalHasVoted[i][msg.sender]
            ) {
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
    function getOngoingProposal(
        uint256 disasterId
    ) external view returns (uint256[] memory) {
        uint256[] memory ongoingProposals = new uint256[](proposalCount);
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].disasterId == disasterId &&
                !proposals[i].approved &&
                block.timestamp <= proposals[i].votingDeadline
            ) {
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
    function getProposalDetails(
        uint256 proposalId
    )
        external 
        view
        returns (
            address creator,            // 修改: 從 uint256 id 改為 address
            string memory proposalName, // 修改: 從 title 改為 proposalName
            uint256 amount,            // 新增: 金額
            uint256 startedDate,
            uint256 dueDate,
            bool canFinalize,
            string memory previewCID,  
            string memory zipCID,      // 修改: 改用 proofCid 
            uint256 total_avail_count,
            uint256 support_count,
            uint256 reject_count
        )
    {
        Proposal storage proposal = proposals[proposalId];
        
        return (
            proposal.proposer,         // creator
            proposal.title,           // proposalName
            proposal.amount,          // amount
            proposal.votingDeadline - VOTING_PERIOD,  // startedDate 
            proposal.votingDeadline,  // dueDate
            !proposal.approved && block.timestamp > proposal.votingDeadline, // canFinalize
            proposal.photoCid,        // previewCID
            proposal.proofCid,        // zipCID (改用 proofCid)
            votingPower[proposal.disasterId][msg.sender], // total_avail_count
            proposal.approveVotes,    // support_count  
            proposal.rejectVotes      // reject_count
        );
    }

    // ====== Utility Functions ======
    // function toString(address account) internal pure returns (string memory) {
    //     return toHexString(uint256(uint160(account)), 20);
    // }

    // // 將數值轉換為十六進制字串
    // function toHexString(
    //     uint256 value,
    //     uint256 length
    // ) internal pure returns (string memory) {
    //     bytes16 _SYMBOLS = "0123456789abcdef";
    //     bytes memory buffer = new bytes(2 * length + 2);
    //     buffer[0] = "0";
    //     buffer[1] = "x";
    //     for (uint256 i = 2 * length + 1; i > 1; --i) {
    //         buffer[i] = _SYMBOLS[value & 0xf];
    //         value >>= 4;
    //     }
    //     return string(buffer);
    // }

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
