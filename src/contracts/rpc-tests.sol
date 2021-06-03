pragma solidity >=0.5.15 <0.6.0;

import "ds-test/test.sol";
import "./addresses.sol";
import "./interfaces.sol";
import "tinlake-title/title.sol";
import {Assertions} from "./assertions.sol";

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
        initRPC();
    }

    function initRPC() public {
        self = address(this);
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        root = RootLike(ROOT_CONTRACT);
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
        dai = ERC20Like(TINLAKE_CURRENCY);
        registry = new Title("TEST", "TEST");

        // cheat: give testContract permissions on root contract by overriding storage
        // storage slot for permissions => keccak256(key, mapslot) (mapslot = 0)
        hevm.store(ROOT_CONTRACT, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

        // todo fetch current block timestamp from chain
        // 21. April 2020
        hevm.warp(1618991883 + 2 days);
    }

    function investTranches() public {
        // pre invest state
        uint preReserveDaiBalance = dai.balanceOf(RESERVE);

        uint preMakerDebt = clerk.debt();

        // get admin super powers
        root.relyContract(POOL_ADMIN, self);
        // whitelist self for tin & drop
        admin.relyAdmin(self);
        admin.updateSeniorMember(self, uint(- 1));
        admin.updateJuniorMember(self, uint(- 1));

        // get super powers on DAI contract
        hevm.store(TINLAKE_CURRENCY, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

        // mint DAI
        uint maxInvest = (assessor.maxReserve() - assessor.totalBalance()) / 2;
        // make sure investment amount does not brek max reserve
        dai.mint(self, maxInvest);

        uint seniorInvest = maxInvest / 2;
        uint juniorInvest = maxInvest - seniorInvest;

        // invest tranches
        dai.approve(SENIOR_TRANCHE, seniorInvest);
        // invest senior
        senior.supplyOrder(seniorInvest);

        dai.approve(JUNIOR_TRANCHE, juniorInvest);
        // invest junior
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
        assertEqTol(tin.balanceOf(self), tinExpected, "rpc#1");
        assertEqTol(drop.balanceOf(self), dropExpected, "rpc#2");

        uint wipeAmount = assertMakerDebtReduced(preMakerDebt, maxInvest);
        // calc wipe amount for maker
        uint reserveIncrease = maxInvest - wipeAmount;
        // calc reserve increase
        assertEqTol(assessor.totalBalance(), preReserveDaiBalance + reserveIncrease, "rpc#3");
        // check reserve balance increased correctly
        assertEqTol(preMakerDebt - wipeAmount, clerk.debt(), "rpc#4");
        // check maker debt reduced correctly
    }


    function appraiseNFT(uint tokenId, uint nftPrice, uint maturityDate) public {
        root.relyContract(FEED, self);
        bytes32 nftId = keccak256(abi.encodePacked(address(registry), tokenId));
        nav.update(nftId, nftPrice, 0);
        nav.file("maturityDate", nftId, maturityDate);
    }

    function raiseCreditLine(uint raiseAmount) public {
        uint preCreditline = clerk.creditline();
        root.relyContract(CLERK, self);
        clerk.raise(raiseAmount);
        assertEq(clerk.creditline(), safeAdd(preCreditline, raiseAmount));
    }

    function borrowLoan(uint loanId, uint borrowAmount) public {
        uint preDaiBalance = dai.balanceOf(self);
        // borrow
        shelf.borrow(loanId, borrowAmount);
        // withdraw
        shelf.withdraw(loanId, borrowAmount, self);
        // assert currency received
        assertEq(dai.balanceOf(self), preDaiBalance + borrowAmount);
    }

    function repayLoan(uint loanId, uint repayAmount) public {
        dai.mint(self, repayAmount);
        dai.approve(SHELF, uint(- 1));
        uint preReserveBalance = dai.balanceOf(self);
        uint preDaiBalance = dai.balanceOf(self);
        // repay debt
        shelf.repay(loanId, repayAmount);
        // assert currency paid
        assertEq(dai.balanceOf(self), preDaiBalance - repayAmount);
    }

    function testLoanCycleWithMaker() public {
        root.relyContract(address(assessor), address(this));
        assessor.file("maxReserve", 1000000000000 * 1 ether);

        investTranches();

        // issue nft
        uint tokenId = registry.issue(self);
        // issue loan
        uint loanId = shelf.issue(address(registry), tokenId);

        // raise creditline
        uint raiseAmount = 100 ether;
        raiseCreditLine(raiseAmount);

        // appraise nft
        uint totalAvailable = assessor.totalBalance();
        uint nftPrice = totalAvailable * 2;
        uint maturityDate = now + 2 weeks;
        appraiseNFT(tokenId, nftPrice, maturityDate);

        // lock asset nft
        registry.setApprovalForAll(SHELF, true);
        shelf.lock(loanId);
        // get loan ceiling
        uint ceiling = (nav.ceiling(loanId));

        // borrow loan with half of the creditline
        uint borrowAmount = reserve.totalBalance() + clerk.creditline() / 2;
        uint preMakerDebt = clerk.debt();

        borrowLoan(loanId, borrowAmount);

        // check debt increase in maker
        assertEqTol(clerk.debt(), preMakerDebt + (clerk.creditline() / 2) ,"clerk debt");

        // jump 5 days into the future
        hevm.warp(now + 5 days);

        // repay entire loan debt
        uint debt = pile.debt(loanId);
        // repayment should reduce maker debt
        preMakerDebt = clerk.debt();
        repayLoan(loanId, debt);
        assertTrue(clerk.debt() < preMakerDebt);
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
