pragma solidity >=0.5.15 <0.6.0;

import "ds-test/test.sol";
import "./addresses.sol";
import "./interfaces.sol";
import "lib/tinlake-title/src/title.sol";
import "./assertions.sol";

contract Hevm {
    function warp(uint256) public;
    function store(address, bytes32, bytes32) public;
}

contract TinlakeRPCTests is Assertions, TinlakeAddresses {
    Hevm public hevm;
    RootLike root;
    IPoolAdmin admin;
    IAssessor assessor;
    IOperator junior;
    IOperator senior;
    ICoordinator coordinator;
    INavFeed nav;
    IShelf shelf;
    IPile pile;
    IReserve reserve;
    IClerk clerk;
    Title registry;
    ERC20Like dai;
    ERC20Like tin;
    ERC20Like drop;

    address self;

    function setUp() public {
        self = address(this);
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        root = RootLike(ROOT);
        admin = IPoolAdmin(POOL_ADMIN);
        nav = INavFeed(FEED);
        shelf = IShelf(SHELF);
        pile = IPile(PILE);
        assessor = IAssessor(ASSESSOR);
        senior = IOperator(SENIOR_OPERATOR);
        junior = IOperator(JUNIOR_OPERATOR);
        coordinator = ICoordinator(COORDINATOR);
        reserve = IReserve(RESERVE);
        clerk = IClerk(CLERK);
        tin = ERC20Like(JUNIOR_TOKEN);
        drop = ERC20Like(SENIOR_TOKEN);
        dai = ERC20Like(DAI);
        registry = new Title("TEST", "TEST");

        // cheat: give testContract permissions on root contract by overriding storage
        // storage slot for permissions => keccak256(key, mapslot) (mapslot = 0)
       hevm.store(ROOT, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

        // todo fetch current block timestamp from chain
        // 21. April 2020
        hevm.warp(1618991883);
    }

    function investTranches() public {
        // pre invest state

        emit log_named_uint("block.timestamp", now);

        uint preReserveDaiBalance = dai.balanceOf(RESERVE);
        uint preMakerDebt = clerk.debt();

       // get admin super powers
       root.relyContract(POOL_ADMIN, self);
       // whitelist self for tin & drop
       admin.relyAdmin(self);
       admin.updateSeniorMember(self, uint(-1));
       admin.updateJuniorMember(self, uint(-1));

        // get super powers on DAI contract
       hevm.store(DAI, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

       // mint DAI
       uint maxInvest = (assessor.maxReserve() - assessor.totalBalance()) / 2; // make sure investment amount does not brek max reserve
       dai.mint(self, maxInvest);

       uint seniorInvest = maxInvest / 2;
       uint juniorInvest = maxInvest - seniorInvest;

       // invest tranches
       dai.approve(SENIOR_TRANCHE, seniorInvest); // invest senior
       senior.supplyOrder(seniorInvest);

       dai.approve(JUNIOR_TRANCHE, juniorInvest); // invest junior
       junior.supplyOrder(juniorInvest);

       // close epoch & disburse
       hevm.warp(now + coordinator.challengeTime());
       coordinator.closeEpoch();
       senior.disburse();
       junior.disburse();

       // calc expected token balances for tin & drop
       uint tinPrice = assessor.calcJuniorTokenPrice(nav.approximatedNAV(), 0);
       uint dropPrice = assessor.calcSeniorTokenPrice(nav.approximatedNAV(), 0);
       uint tinExpected = rdiv(juniorInvest, tinPrice);
       uint dropExpected = rdiv(seniorInvest, dropPrice);

       // check correct tin & drop token received
       assertEqWithTolarence(tin.balanceOf(self), tinExpected);
       assertEqWithTolarence(drop.balanceOf(self), dropExpected);

       uint wipeAmount = assertMakerDebtReduced(preMakerDebt, maxInvest); // calc wipe amount for maker
       uint reserveIncrease = maxInvest - wipeAmount; // calc reserve increase
       assertEqWithTolarence(assessor.totalBalance(), preReserveDaiBalance + reserveIncrease); // check reserve balance increased correctly
       assertEqWithTolarence(preMakerDebt - wipeAmount, clerk.debt()); // check maker debt reduced correctly
    }

    function testLoanCycle() public {
        investTranches();
        uint preDaiBalance = dai.balanceOf(self);

        // issue nft
        uint tokenId = registry.issue(self);

        // issue loan
        uint loanId = shelf.issue(address(registry), tokenId);

        // set nft value
        root.relyContract(FEED, self);
        bytes32 nftId = keccak256(abi.encodePacked(address(registry), tokenId));
        uint reserveBalance = assessor.totalBalance();
        emit log_named_uint("balance", reserveBalance);
        emit log_named_uint("available", reserve.currencyAvailable());
        uint nftPrice = reserveBalance / 2; // make sure nft/loan value smaller then reserve balance
        emit log_named_uint("price", nftPrice);
        nav.update(nftId, nftPrice, 0);
        nav.file("maturityDate", nftId, uint(-1));

        // lock nft
        registry.setApprovalForAll(SHELF, true);
        shelf.lock(loanId);
        // get loan ceiling
        uint ceiling = (nav.ceiling(loanId));
        emit log_named_uint("ceiling", ceiling);
        // borrow
        shelf.borrow(loanId, ceiling);
//        // withdraw
//        shelf.withdraw(loanId, ceiling, self);
//
//        // assert currency received
//        assertEq(dai.balanceOf(self), preDaiBalance + ceiling);
//
//        // warp
//        // hevm.warp(now + 5 days);
//        // uint debt = pile.debt(loanId);
//        // dai.mint(debt, self);
//        // uint preReserveBalance = dai.balanceOf(self);
//        // approve currency
//        // shelf.repay(loanId, debt);
//        // assert reserve increase
//        // assert maker repaid

    }

    function testLoanCycleWithMaker() public {
        // raise creditline if not done yet
        // loan amount higher then reserve
        // testLoanCycle
    }

    // helper
    function assertHasPermissions(address con, address ward) public {
        uint perm = IAuth(con).wards(ward);
        assertEq(perm, 1);
    }

    function assertHasNoPermissions(address con, address ward) public {
        uint perm = IAuth(con).wards(ward);
        assertEq(perm, 0);
    }

    function assertMakerDebtReduced(uint preDebt, uint investmentAmount) public returns (uint) {
        if (preDebt > 1) {
            if (preDebt > investmentAmount) {
                assertEq(clerk.debt(), (preDebt - investmentAmount));
                return investmentAmount;
            } else {
                assert(clerk.debt() <= 1);
                return preDebt;
            }
        }
        return 0;
    }

}
