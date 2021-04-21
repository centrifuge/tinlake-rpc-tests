pragma solidity >=0.5.15 <0.6.0;

interface IAuth {
    function rely(address) external;
    function deny(address) external;
    function wards(address) external returns(uint);
}

interface IPoolAdmin {
    function updateSeniorMember(address usr, uint256 validUntil) external;
    function updateJuniorMember(address usr, uint256 validUntil) external;
    function relyAdmin(address usr) external;
}

interface IAssessor {
    function maxReserve() external returns (uint);
    function totalBalance() external returns (uint);
    function calcJuniorTokenPrice(uint nav_, uint) external view returns(uint);
    function calcSeniorTokenPrice(uint nav_, uint) external view returns(uint);
}

interface INavFeed {
    function approximatedNAV() external returns (uint);
    function update(bytes32 nftID, uint value) external;
    function update(bytes32 nftID, uint value, uint risk) external;
    function file(bytes32 what, bytes32 nftID_, uint maturityDate_) external;
    function ceiling(uint loan) external view returns(uint);
}

interface IOperator {
    function supplyOrder(uint amount) external;
    function disburse() external returns(uint payoutCurrencyAmount, uint payoutTokenAmount, uint remainingSupplyCurrency,  uint remainingRedeemToken);
}

contract IShelf {
    function lock(uint loan) external;
    function unlock(uint loan) external;
    function issue(address registry, uint token) public returns (uint loan);
    function close(uint loan) external;
    function borrow(uint loan, uint wad) external;
    function withdraw(uint loan, uint wad, address usr) external;
    function repay(uint loan, uint wad) external;
    function shelf(uint loan) public returns(address registry,uint256 tokenId,uint price,uint principal, uint initial);
    function file(bytes32 what, uint loan, address registry, uint nft) external;
}

contract IPile  {
    function debt(uint loan) public returns(uint);
}

interface IReserve {
    function currencyAvailable() external returns(uint);
    function totalBalance() external returns(uint);
}

interface IClerk {
    function debt() external view returns(uint);
    function creditline() external view returns(uint);
    function raise(uint amount) external;
}

interface ICoordinator {
    function closeEpoch() external;
    function executeEpoch() external;
    function challengeTime() external returns (uint);
}

interface RootLike {
    function relyContract(address contractAddr, address addr) external;
}

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint) external returns (bool);
    function mint(address, uint256) external;
    function burn(address, uint256) external;
    function totalSupply() external view returns (uint256);
    function approve(address, uint) external;
    function ceiling(uint loan) external view returns(uint);
}

interface IRegistry {
   function issue(address) external returns (uint);
}
