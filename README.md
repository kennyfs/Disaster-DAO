# Disaster-DAO

113-2 去中心化應用程式之設計實務 期末報告  
直接把善款分給救援者、重建家園者的 DAO

## DisasterResponse 合約 API 文件

### 公開變數

- `mapping(uint256 => Disaster) public disasters`: 儲存所有災難的資料，鍵為災難 ID。
- `mapping(uint256 => Request) public requests`: 儲存所有災難請求的資料，鍵為請求 ID。
- `mapping(uint256 => Proposal) public proposals`: 儲存所有請款提案的資料，鍵為提案 ID。
- `mapping(uint256 => mapping(address => uint256)) public donations`: 儲存用戶對每個災難的捐款金額，鍵為災難 ID 和捐款者地址。
- `mapping(uint256 => mapping(address => uint256)) public votingPower`: 儲存用戶在每個災難中的投票權，鍵為災難 ID 和用戶地址。
- `mapping(address => bool) public admins`: 儲存管理員權限狀態，鍵為位址，管理員則對應到 true，非管理員或曾經是管理員但被移除則會是 false。
- `address[] public adminList`: 儲存所有管理員地址的陣列。
- `uint256 public disasterCount`: 已創建的災難總數。
- `uint256 public requestCount`: 已提交的災難請求總數。
- `uint256 public proposalCount`: 已提交的請款提案總數。
- `uint256 public stakeAmount`: 提交災難請求時需質押的金額，預設為 0.01 ETH。
- `uint256 public newRewardAmount`: 災難請求通過時提議者可獲得的獎勵金額，預設為 0.0005 ETH。
- `uint256 public constant VOTING_PERIOD`: 投票期間，固定為 3 天。
- `uint256 public constant TIMELOCK`: 請款提案的鎖定期，固定為 1 天（目前在程式碼中未強制執行）。
- `uint256 public constant MIN_APPROVE_RATIO_NEW`: 新增災難請求的最低同意票比例，固定為 5%。
- `uint256 public constant MIN_APPROVE_RATIO_PROOF`: 請款提案的最低同意票比例，固定為 25%。
- `uint256 public constant VOTING_POWER_BASE`: 投票權計算的基準單位，固定為 1e6。
- `uint256 public constant DEFAULT_DISASTER_DURATION`: 災難的預設持續時間，固定為 180 天。
- `mapping(uint256 => mapping(address => bool)) public requestHasVoted`: 記錄用戶是否已對某個災難請求投票。
- `mapping(uint256 => mapping(address => bool)) public requestVoteType`: 記錄用戶對某個災難請求的投票類型（贊成 true 或反對 false）。
- `mapping(uint256 => mapping(address => bool)) public proposalHasVoted`: 記錄用戶是否已對某個請款提案投票。
- `mapping(uint256 => mapping(address => bool)) public proposalVoteType`: 記錄用戶對某個請款提案的投票類型（贊成 true 或反對 false）。

---

### 公開函數


#### 管理員相關

##### `addAdmin`

- 呼叫：`addAdmin(address admin)`
- 權限：僅合約擁有者 (`onlyOwner`)
- 功能：新增一個管理員地址到 `admins` 映射和 `adminList` 陣列中。
- 參數：
  - `admin` (`address`)：要新增的管理員地址。
- 回傳：無
- 注意：如果該地址已是管理員，則無任何變更。

##### `removeAdmin`

- 呼叫：`removeAdmin(address admin)`
- 權限：僅合約擁有者 (`onlyOwner`)
- 功能：移除一個管理員，將其從 `admins` 映射和 `adminList` 陣列中刪除。
- 參數：
  - `admin` (`address`)：要移除的管理員地址。
- 回傳：無
- 注意：如果該地址不是管理員，則無任何變更。

##### `getAdminCount`

- 呼叫：`getAdminCount()`
- 功能：返回當前管理員的總數。
- 回傳：`uint256` - 管理員數量（即 `adminList` 陣列的長度）。
- 權限：公開，無限制。

---

#### 災難請求相關

##### `addRequest`

- 呼叫：`addRequest(string title, string photoCid, string description, address residualAddress)`
- 需支付：`stakeAmount` (預設 0.01 ETH，但要留意應以 Wei 為單位，因此是 $10^{16}$ Wei)
- 功能：提交一個新的災難請求，等待管理員投票審核。
- 參數：
  - `title` (`string`)：災難請求的標題。
  - `photoCid` (`string`)：災難照片的 IPFS CID，用於預覽使用。
  - `description` (`string`)：災難描述。
  - `residualAddress` (`address`)：災難結束後剩餘資金的接收地址。
- 回傳：無
- 事件：`DisasterRequested(uint256 indexed requestId, address proposer, string title)`
- 錯誤：
  - 如果支付的 ETH 不等於 `stakeAmount`，拋出 "Must stake 0.01 ETH"。

##### `voteRequest`

- 呼叫：`voteRequest(uint256 requestId, bool approve)`
- 權限：僅管理員 (`admins`)
- 功能：對指定的災難請求進行投票，每個管理員擁有 1 票。
- 參數：
  - `requestId` (`uint256`)：要投票的請求 ID。
  - `approve` (`bool`)：贊成 (`true`) 或反對 (`false`)。
- 回傳：無
- 事件：`DisasterVoted(uint256 indexed requestId, address voter, bool approve)`
- 錯誤：
  - 如果呼叫者不是管理員，拋出 "Only admins can vote"。
  - 如果投票已結束，拋出 "Voting period ended"。
  - 如果已投票，拋出 "Already voted"。

##### `finalizeDisaster`

- 呼叫：`finalizeDisaster(uint256 requestId)`
- 權限：僅管理員 (`admins`)
- 功能：根據投票結果最終化災難請求。若通過，創建新的災難並退還質押金加獎勵；若未通過，退還部分質押金。
- 參數：
  - `requestId` (`uint256`)：要最終化的請求 ID。
- 回傳：無
- 事件：`DisasterCreated(uint256 indexed disasterId)`（如果通過）
- 錯誤：
  - 如果呼叫者不是管理員，拋出 "Only admins can finalize a disaster"。
  - 如果請求已最終化，拋出 "Already finalized"。
- 注意：為了使災難能儘快建立以開始募款，沒有設計 timeLock，但若呼叫此函數時票數不足，則會直接視為請求失敗，所以需要限制僅管理員能呼叫。

#### 請款提案相關

##### `submitProposal`

- 呼叫：`submitProposal(uint256 disasterId, string title, uint256 amount, string description, string photoCid, string proofCid)`
- 功能：提交一個請款提案，供捐款者投票。
- 參數：
  - `disasterId` (`uint256`)：相關災難的 ID。
  - `title` (`string`)：提案標題。
  - `amount` (`uint256`)：請款金額（單位：wei）。
  - `description` (`string`)：提案描述。
  - `photoCid` (`string`)：提案照片的 IPFS CID，用於預覽使用。
  - `proofCid` (`string`)：證明文件的 IPFS CID。
- 回傳：無
- 事件：`ProposalProposed(uint256 indexed proposalId, uint256 disasterId, address proposer, string title)`
- 錯誤：
  - 如果災難已結束，拋出 "Disaster not active"。

##### `voteProposal`

- 呼叫：`voteProposal(uint256 proposalId, bool approve)`
- 功能：對指定的請款提案進行投票，投票權基於捐款金額。
- 參數：
  - `proposalId` (`uint256`)：要投票的提案 ID。
  - `approve` (`bool`)：贊成 (`true`) 或反對 (`false`)。
- 回傳：無
- 事件：`ProposalVoted(uint256 indexed proposalId, address voter, bool approve)`
- 錯誤：
  - 如果投票已結束，拋出 "Voting period ended"。
  - 如果已投票，拋出 "Already voted"。
  - 如果用戶無投票權，拋出 "No voting power for this disaster"。

##### `finalizeProposal`

- 呼叫：`finalizeProposal(uint256 proposalId)`
- 功能：根據投票結果最終化請款提案。若通過，轉帳請款金額給提議者。
- 參數：
  - `proposalId` (`uint256`)：要最終化的提案 ID。
- 回傳：無
- 事件：`ProposalApproved(uint256 indexed proposalId)`（如果通過）
- 錯誤：
  - 如果提案已通過，拋出 "Already approved"。
  - 如果票數不足，拋出 "Not enough votes"。
  - 如果資金不足，拋出 "Insufficient funds"。

---

#### 捐款相關

##### `donate`

- 呼叫：`donate(uint256 disasterId)`
- 需支付：任意 ETH 金額
- 功能：對指定的災難進行捐款，捐款金額決定投票權。並且會回溯此使用者之前投票過的所有提案，調整至新的投票權數量。
- 參數：
  - `disasterId` (`uint256`)：要捐款的災難 ID。
- 回傳：無
- 事件：`Donated(uint256 indexed disasterId, address indexed donor, uint256 amount, uint256 votingPower)`
- 錯誤：
  - 如果捐款金額為 0，拋出 "Donation must be greater than 0"。
  - 如果災難已結束，拋出 "Disaster not active"。

---

#### 災難結束

##### `endDisaster`

- 呼叫：`endDisaster(uint256 disasterId)`
- 功能：結束指定的災難，將剩餘資金轉移到 `residualAddress`。
- 參數：
  - `disasterId` (`uint256`)：要結束的災難 ID。
- 回傳：無
- 錯誤：
  - 如果災難尚未到期，拋出 "Disaster not ended"。

---

#### 查詢函數

##### `getDisasterList`

- 呼叫：`getDisasterList()`
- 功能：返回所有災難的列表。
- 回傳：`Disaster[]` - 災難結構體陣列。

##### `getVotableDisaster`

- 呼叫：`getVotableDisaster(address voter)`
- 功能：返回指定用戶可以投票的災難 ID 列表。
- 參數：
  - `voter` (`address`)：查詢的用戶地址。
- 回傳：`uint256[]` - 可投票的災難 ID 陣列。

##### `getVotableRequests`

- 呼叫：`getVotableRequests()`
- 功能：返回當前可投票的災難請求列表（僅限管理員）。
- 回傳：`Request[]` - 可投票的災難請求陣列。

##### `getVotableProposals`

- 呼叫：`getVotableProposals(uint256 disasterId)`
- 功能：返回指定災難中當前可投票的請款提案列表。
- 參數：
  - `disasterId` (`uint256`)：相關災難的 ID。
- 回傳：`Proposal[]` - 可投票的請款提案陣列。

##### `getNewRequest`

- 呼叫：`getNewRequest(uint256 requestId)`
- 功能：返回指定災難請求的詳細資訊。
- 參數：
  - `requestId` (`uint256`)：請求 ID。
- 回傳：元組
  - `uint256 id`
  - `string title`
  - `string photoCid`
  - `address proposer`
  - `bool ended`（修正文件中的 `approved` 為 `ended`）
  - `uint256 approveVotes`
  - `uint256 rejectVotes`
  - `uint256 votingDeadline`

##### `getProposal`

- 呼叫：`getProposal(uint256 proposalId)`
- 功能：返回指定請款提案的詳細資訊。
- 參數：
  - `proposalId` (`uint256`)：提案 ID。
- 回傳：元組
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

##### `getMyDonationsCount`

- 呼叫：`getMyDonationsCount()`
- 功能：返回呼叫者捐款過的災難數量。
- 回傳：`uint256` - 捐款過的災難數量。

##### `getMyDonations`

- 呼叫：`getMyDonations()`
- 功能：返回呼叫者在指定範圍內的捐款記錄。
- 回傳：`DonationRecord[]` - 捐款記錄陣列。

##### `getDueDisaster`

- 呼叫：`getDueDisaster()`
- 功能：返回已到期的災難 ID 列表。
- 回傳：`uint256[]` - 已到期災難 ID 陣列。

##### `getOngoingDisaster`

- 呼叫：`getOngoingDisaster()`
- 功能：返回正在進行中的災難 ID 列表。
- 回傳：`uint256[]` - 進行中災難 ID 陣列。

##### `getUnvoteProposal`

- 呼叫：`getUnvoteProposal(uint256 disasterId)`
- 功能：返回呼叫者尚未投票的請款提案 ID 列表。
- 參數：
  - `disasterId` (`uint256`)：相關災難的 ID。
- 回傳：`uint256[]` - 未投票提案 ID 陣列。

##### `getVotedProposal`

- 呼叫：`getVotedProposal(uint256 disasterId)`
- 功能：返回呼叫者已投票的請款提案 ID 列表。
- 參數：
  - `disasterId` (`uint256`)：相關災難的 ID。
- 回傳：`uint256[]` - 已投票提案 ID 陣列。

##### `getOngoingProposal`

- 呼叫：`getOngoingProposal(uint256 disasterId)`
- 功能：返回指定災難中正在進行中的請款提案 ID 列表。
- 參數：
  - `disasterId` (`uint256`)：相關災難的 ID。
- 回傳：`uint256[]` - 進行中提案 ID 陣列。

##### `getProposalDetails`

- 呼叫：`getProposalDetails(uint256 proposalId)`
- 功能：返回指定請款提案的詳細資訊，包括投票結果。
- 參數：
  - `proposalId` (`uint256`)：提案 ID。
- 回傳：元組
  - `address creator`
  - `string proposalName`
  - `uint256 amount`
  - `uint256 startedDate`
  - `uint256 dueDate`
  - `bool canFinalize`
  - `string previewCID`
  - `string zipCID`
  - `VotingResult voting_result`（包含 `total_avail_count`, `support_count`, `reject_count`）

---

### 結構體

#### `Disaster`

- 用途：儲存災難的相關資訊。
- 欄位：
  - `string name`: 災難名稱。
  - `string photoCid`: 災難照片的 IPFS CID。
  - `string description`: 災難描述。
  - `uint256 deadline`: 災難截止日期（開始時間 + 180 天）。
  - `uint256 balance`: 災難的資金餘額。
  - `uint256 totalVotes`: 災難的總投票權。
  - `address residualAddress`: 剩餘資金的接收地址。

#### `Request`

- 用途：儲存災難請求的相關資訊。
- 欄位：
  - `uint256 id`: 請求 ID。
  - `string title`: 請求標題。
  - `string photoCid`: 請求照片的 IPFS CID。
  - `string description`: 請求描述。
  - `address proposer`: 提議者地址。
  - `bool ended`: 是否已最終化。
  - `uint256 approveVotes`: 贊成票數。
  - `uint256 rejectVotes`: 反對票數。
  - `uint256 votingDeadline`: 投票截止日期。
  - `address residualAddress`: 剩餘資金的接收地址。

#### `Proposal`

- 用途：儲存請款提案的相關資訊。
- 欄位：
  - `uint256 id`: 提案 ID。
  - `uint256 disasterId`: 相關災難的 ID。
  - `string title`: 提案標題。
  - `string photoCid`: 提案照片的 IPFS CID。
  - `string description`: 提案描述。
  - `string proofCid`: 證明文件的 IPFS CID。
  - `uint256 amount`: 請款金額（單位：wei）。
  - `address proposer`: 提議者地址。
  - `bool approved`: 是否已通過。
  - `uint256 approveVotes`: 贊成票數。
  - `uint256 rejectVotes`: 反對票數。
  - `uint256 votingDeadline`: 投票截止日期。
  - `uint256 timeLock`: 鎖定期結束時間（目前未強制執行）。

#### `DonationRecord`

- 用途：回傳用戶的捐款記錄。
- 欄位：
  - `uint256 disasterId`: 災難 ID。
  - `string name`: 災難名稱。
  - `address donateAddress`:剩餘資金的接收地址。
  - `string photoCid`: 提案照片的 IPFS CID。
  - `uint256 total_amount`: 捐款總金額（單位：wei）。
  - `uint256 vote_per`: 用戶的投票權。

#### `VotingResult`

- 用途：回傳投票結果。
- 欄位：
  - `uint256 total_avail_count`: 呼叫者的投票權。
  - `uint256 support_count`: 贊成票數。
  - `uint256 reject_count`: 反對票數。

---

> 以上所有函數皆為 external/public，除非特別標註 internal/private。
