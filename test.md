# 在 Remix 上測試合約

目前 testing branch 的變動：不需要過了 timelock 才能 finalize  
需要新增回 main branch 的變動：finalizeDisaster 需要確保回傳的值不能超過合約持有的 ETH 量

## test 1 by kennyfs

使用預設的 Remix VM(Prague)，commit 5103e57171af0263b410694bc6b043619ecd4c7c

* 以第一個帳號 deploy，參數 [0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db]，第二、三個帳號，這樣前三個都是 admin
* 以第一個帳號 addRequest，記得要設 value 為 100 Finney($10^-3$ Ether)，=0.1 Ether，參數
  * title: test
  * photoCid: NotARealCID
  * description: earthquake
  * deadline: 123，目前完全沒用到 deadline 參數，所以沒差
  * residualAddress: 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB，第四個帳號
* 目前第一個帳號餘額應該是 99.89...
* 以第一個帳號 voteRequest，參數
  * requestId: 1
  * approve: 1
* 目前第一個帳號餘額應該是 99.99...
* 以第一個帳號 donate，disasterId 1，value 為 100 Finney
* 目前第一個帳號餘額應該是 99.89...
* 以第一個帳號 submitProposal
  * disasterId: 1
  * title: I saved one person.
  * amount: 50000000000000000(wei, 相當 0.05 Ether)
  * description: As title
  * photoCid: NotARealCID1
  * proofCid: NotARealCID2
* 以第一個帳號 voteProposal，
  * proposalId: 1
  * approve: 1
* 以第一個帳號 finalizeProposal，proposalId: 1
* 目前第一個帳號餘額應該是 99.94...
* 以第一個帳號 endDisaster，disasterId: 1
* 目前第四個帳號餘額應該是 100.05...

目前整個流程應該是沒什麼問題，但還需要確保

* 投票門檻正常運作
* 所有查詢運作正常
