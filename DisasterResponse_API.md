# DisasterResponse 合約 API 文件

## 公開變數

- `mapping(uint256 => Disaster) public disasters`
- `mapping(uint256 => Request) public requests`
- `mapping(uint256 => Proposal) public proposals`
- `mapping(uint256 => mapping(address => uint256)) public donations`
- `mapping(uint256 => mapping(address => uint256)) public votingPower`
- `mapping(address => bool) public admins`
- `address[] public adminList`
- `uint256 public disasterCount`
- `uint256 public requestCount`
- `uint256 public proposalCount`
- `uint256 public stakeAmount`
- `uint256 public newRewardAmount`
- `uint256 public constant VOTING_PERIOD`
- `uint256 public constant TIMELOCK`
- `uint256 public constant MIN_APPROVE_RATIO_NEW`
- `uint256 public constant MIN_APPROVE_RATIO_PROOF`
- `uint256 public constant VOTING_POWER_BASE`
- `uint256 public constant DEFAULT_DISASTER_DURATION`
- `mapping(uint256 => mapping(address => bool)) public requestHasVoted`
- `mapping(uint256 => mapping(address => bool)) public requestVoteType`
- `mapping(uint256 => mapping(address => bool)) public proposalHasVoted`
- `mapping(uint256 => mapping(address => bool)) public proposalVoteType`

## 公開函數

### 管理員相關

#### addAdmin
- 呼叫：`addAdmin(address admin)`
- 權限：onlyOwner
- 回傳：無

#### removeAdmin
- 呼叫：`removeAdmin(address admin)`
- 權限：onlyOwner
- 回傳：無

#### getAdminCount
- 呼叫：`getAdminCount()`
- 回傳：`uint256` 管理員數量

---

### 災難請求相關

#### addRequest
- 呼叫：`addRequest(string title, string photoCid, string description, address residualAddress)`
- 需支付：`stakeAmount` (0.01 ETH)
- 回傳：無

#### voteRequest
- 呼叫：`voteRequest(uint256 requestId, bool approve)`
- 權限：僅 admin
- 回傳：無

#### finalizeDisaster
- 呼叫：`finalizeDisaster(uint256 requestId)`
- 權限：僅 admin
- 回傳：無

---

### 請款提案相關

#### submitProposal
- 呼叫：`submitProposal(uint256 disasterId, string title, uint256 amount, string description, string photoCid, string proofCid)`
- 回傳：無

#### voteProposal
- 呼叫：`voteProposal(uint256 proposalId, bool approve)`
- 回傳：無

#### finalizeProposal
- 呼叫：`finalizeProposal(uint256 proposalId)`
- 回傳：無

---

### 捐款相關

#### donate
- 呼叫：`donate(uint256 disasterId)`
- 需支付：任意 ETH
- 回傳：無

---

### 災難結束

#### endDisaster
- 呼叫：`endDisaster(uint256 disasterId)`
- 回傳：無

---

### 查詢函數

#### getDisasterList
- 呼叫：`getDisasterList()`
- 回傳：`Disaster[]` 災難結構體陣列

#### getVotableDisaster
- 呼叫：`getVotableDisaster(address voter)`
- 回傳：`uint256[]` 可投票災難 ID 陣列

#### getVotableRequests
- 呼叫：`getVotableRequests()`
- 回傳：`Request[]` 可投票災難請求陣列

#### getVotableProposals
- 呼叫：`getVotableProposals(uint256 disasterId)`
- 回傳：`Proposal[]` 可投票請款提案陣列

#### getNewRequest
- 呼叫：`getNewRequest(uint256 requestId)`
- 回傳：tuple
  - `uint256 id`
  - `string title`
  - `string photoCid`
  - `address proposer`
  - `bool approved`
  - `uint256 approveVotes`
  - `uint256 rejectVotes`
  - `uint256 votingDeadline`

#### getProposal
- 呼叫：`getProposal(uint256 proposalId)`
- 回傳：tuple
  - `uint256 id`
  - `uint256 disasterId`
  - `string title`
  - `string photoCid`
  - `uint256 amount`
  - `address proposer`
  - `bool approved`
  - `uint256 approveVotes`
  - `uint256 rejectVotes`
  - `uint256 votingDeadline`

#### getMyDonationsCount
- 呼叫：`getMyDonationsCount()`
- 回傳：`uint256` 用戶捐款過的災難數量

#### getMyDonations
- 呼叫：`getMyDonations(uint256 from, uint256 to)`
- 回傳：`DonationRecord[]` 捐款紀錄陣列

#### getDueDisaster
- 呼叫：`getDueDisaster()`
- 回傳：`uint256[]` 已到期災難 ID 陣列

#### getOngoingDisaster
- 呼叫：`getOngoingDisaster()`
- 回傳：`uint256[]` 進行中災難 ID 陣列

#### getUnvoteProposal
- 呼叫：`getUnvoteProposal(uint256 disasterId)`
- 回傳：`uint256[]` 用戶尚未投票的提案 ID 陣列

#### getVotedProposal
- 呼叫：`getVotedProposal(uint256 disasterId)`
- 回傳：`uint256[]` 用戶已投票的提案 ID 陣列

#### getOngoingProposal
- 呼叫：`getOngoingProposal(uint256 disasterId)`
- 回傳：`uint256[]` 進行中提案 ID 陣列

#### getProposalDetails
- 呼叫：`getProposalDetails(uint256 proposalId)`
- 回傳：tuple
  - `address creator`
  - `string proposalName`
  - `uint256 amount`
  - `uint256 startedDate`
  - `uint256 dueDate`
  - `bool canFinalize`
  - `string previewCID`
  - `string zipCID`
  - `VotingResult voting_result`

---

## 結構體

### Disaster
- `string name`
- `string photoCid`
- `string description`
- `uint256 deadline`
- `uint256 balance`
- `uint256 totalVotes`
- `address residualAddress`

### Request
- `uint256 id`
- `string title`
- `string photoCid`
- `string description`
- `address proposer`
- `bool ended`
- `uint256 approveVotes`
- `uint256 rejectVotes`
- `uint256 votingDeadline`
- `address residualAddress`

### Proposal
- `uint256 id`
- `uint256 disasterId`
- `string title`
- `string photoCid`
- `string description`
- `string proofCid`
- `uint256 amount`
- `address proposer`
- `bool approved`
- `uint256 approveVotes`
- `uint256 rejectVotes`
- `uint256 votingDeadline`
- `uint256 timeLock`

### DonationRecord
- `uint256 disasterId`
- `string name`
- `uint256 total_amount`
- `uint256 vote_per`

### VotingResult
- `uint256 total_avail_count`
- `uint256 support_count`
- `uint256 reject_count`

---

> 以上所有函數皆為 external/public，除非特別標註 internal/private。
