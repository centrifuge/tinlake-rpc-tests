// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.0;

interface TAuth {
    function rely(address) external;
    function deny(address) external;
    function wards(address) external returns(uint);
}

interface T_PoolAdmin {
    function updateSeniorMember(address usr, uint256 validUntil) external;
    function updateJuniorMember(address usr, uint256 validUntil) external;
    function relyAdmin(address usr) external;
}

interface T_Assessor {
    function maxReserve() external returns (uint);
    function totalBalance() external returns (uint);
    function calcJuniorTokenPrice(uint nav_, uint) external view returns(uint);
    function calcSeniorTokenPrice(uint nav_, uint) external view returns(uint);
    function file(bytes32, uint) external;
}

interface T_NavFeed {
    function approximatedNAV() external returns (uint);
    function update(bytes32 nftID, uint value) external;
    function update(bytes32 nftID, uint value, uint risk) external;
    function file(bytes32 what, bytes32 nftID_, uint maturityDate_) external;
    function ceiling(uint loan) external view returns(uint);
}

interface T_Operator {
    function supplyOrder(uint amount) external;
    function disburse() external returns(uint payoutCurrencyAmount, uint payoutTokenAmount, uint remainingSupplyCurrency,  uint remainingRedeemToken);
}

interface T_Shelf {
    function lock(uint loan) external;
    function unlock(uint loan) external;
    function issue(address registry, uint token) external returns (uint loan);
    function close(uint loan) external;
    function borrow(uint loan, uint wad) external;
    function withdraw(uint loan, uint wad, address usr) external;
    function repay(uint loan, uint wad) external;
    function shelf(uint loan) external returns(address registry,uint256 tokenId,uint price,uint principal, uint initial);
    function file(bytes32 what, uint loan, address registry, uint nft) external;
}

interface T_Pile  {
    function debt(uint loan) external returns(uint);
}

interface T_Reserve {
    function currencyAvailable() external returns(uint);
    function totalBalance() external returns(uint);
}

interface T_Clerk {
    function debt() external view returns(uint);
    function creditline() external view returns(uint);
    function raise(uint amount) external;
}

interface T_Tranche {
    function epochs(uint epochID) external returns(uint redeemFulfill, uint supplyFulfill, uint tokenPrice);
}

interface T_Coordinator {
    function closeEpoch() external;
    function executeEpoch() external;
    function submissionPeriod() external returns(bool);
    function challengeTime() external returns (uint);
    function epochSeniorTokenPrice() external returns (uint);
    function epochJuniorTokenPrice() external returns (uint);
    function lastEpochExecuted() external returns(uint);
}

interface T_RootLike {
    function relyContract(address contractAddr, address addr) external;
}

interface T_ERC20 {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint) external returns (bool);
    function mint(address, uint256) external;
    function burn(address, uint256) external;
    function totalSupply() external view returns (uint256);
    function approve(address, uint) external;
    function ceiling(uint loan) external view returns(uint);
}

interface T_Registry {
   function issue(address) external returns (uint);
}
