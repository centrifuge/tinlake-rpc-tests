// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.0;

import "../../lib/ds-test/src/test.sol";
import "./addresses.sol";
import "./interfaces.sol";
import "../../lib/tinlake-title/src/title.sol";
import {Assertions} from "./assertions.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address, bytes32, bytes32) external;
}

contract TinlakeRPCTests is Assertions, TinlakeAddresses {
    Hevm public hevm;
    T_RootLike root;
    T_PoolAdmin admin;
    T_Assessor assessor;
    T_Operator junior;
    T_Operator senior;
    T_Coordinator coordinator;
    T_NavFeed nav;
    T_Shelf shelf;
    T_Pile pile;
    T_Reserve reserve;
    T_Clerk clerk;
    Title registry;
    T_ERC20 dai;
    T_ERC20 tin;
    T_ERC20 drop;
    T_Tranche seniorTranche;
    T_Tranche juniorTranche;

    address self;

    function setUp() public virtual {
        initRPC();
    }

    function initRPC() public {
        self = address(this);
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        root = T_RootLike(ROOT_CONTRACT);
        admin = T_PoolAdmin(POOL_ADMIN);
        nav = T_NavFeed(FEED);
        shelf = T_Shelf(SHELF);
        pile = T_Pile(PILE);
        assessor = T_Assessor(ASSESSOR);
        senior = T_Operator(SENIOR_OPERATOR);
        junior = T_Operator(JUNIOR_OPERATOR);
        seniorTranche = T_Tranche(SENIOR_TRANCHE);
        juniorTranche = T_Tranche(JUNIOR_TRANCHE);
        coordinator = T_Coordinator(COORDINATOR);
        reserve = T_Reserve(RESERVE);
        clerk = T_Clerk(CLERK);
        tin = T_ERC20(JUNIOR_TOKEN);
        drop = T_ERC20(SENIOR_TOKEN);
        dai = T_ERC20(TINLAKE_CURRENCY);
        registry = new Title("TEST", "TEST");

        // cheat: give testContract permissions on root contract by overriding storage
        // storage slot for permissions => keccak256(key, mapslot) (mapslot = 0)
        hevm.store(ROOT_CONTRACT, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));


        hevm.warp(block.timestamp + 2 days);
    }

    function disburse(uint preMakerDebt, uint, uint seniorInvest, uint juniorInvest) public {
        // close epoch & disburse
        hevm.warp(block.timestamp + coordinator.challengeTime());

        uint lastEpochExecuted = coordinator.lastEpochExecuted();

        senior.disburse();
        junior.disburse();

        (, uint seniorSupplyFulfill, uint seniorPrice) = seniorTranche.epochs(lastEpochExecuted);
        (, uint juniorSupplyFulfill, uint juniorPrice) = juniorTranche.epochs(lastEpochExecuted);


        // effective invested in this epoch
        juniorInvest = rmul(juniorInvest, juniorSupplyFulfill);
        seniorInvest = rmul(seniorInvest, seniorSupplyFulfill);

        uint tinExpected = rdiv(juniorInvest, juniorPrice);
        uint dropExpected = rdiv(seniorInvest, seniorPrice);

        // check correct tin & drop token received
        assertEqTol(tin.balanceOf(self), tinExpected, "rpc#1");
        assertEqTol(drop.balanceOf(self), dropExpected, "rpc#2");

        uint investAmount = safeAdd(seniorInvest, juniorInvest);

        uint wipeAmount = assertMakerDebtReduced(preMakerDebt, investAmount);


        assertEqTol(preMakerDebt - wipeAmount, clerk.debt(), "rpc#3");
        // check maker debt reduced correctly

    }

    function investTranches() public {
        // pre invest state
        uint preReserveDaiBalance = dai.balanceOf(RESERVE);

        uint preMakerDebt = clerk.debt();

        // get admin super powers
        root.relyContract(POOL_ADMIN, self);
        // whitelist self for tin & drop
        admin.relyAdmin(self);
        admin.updateSeniorMember(self, uint(-1));
        admin.updateJuniorMember(self, uint(-1));

        // get super powers on DAI contract
        hevm.store(TINLAKE_CURRENCY, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

        // mint DAI
        uint maxInvest = (assessor.maxReserve() - assessor.totalBalance()) / 2;
        // make sure investment amount does not brek max reserve
        dai.mint(self, maxInvest);

        uint seniorInvest = maxInvest / 2;
        // in Maker pools the minSeniorRatio is zero => more TIN always welcome
        uint juniorInvest = maxInvest - seniorInvest;
        // uint seniorInvest = 1 ether;
        // uint juniorInvest = 1 ether;

        // invest tranches
        dai.approve(SENIOR_TRANCHE, type(uint256).max);
        // invest senior
        senior.supplyOrder(seniorInvest);

        dai.approve(JUNIOR_TRANCHE, type(uint256).max);
        // invest junior
        junior.supplyOrder(juniorInvest);

        coordinator.closeEpoch();

        // todo handle submission period case
        assertTrue(coordinator.submissionPeriod()  == false);

        disburse(preMakerDebt, preReserveDaiBalance, seniorInvest, juniorInvest);
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
        uint maturityDate = block.timestamp + 2 weeks;
        appraiseNFT(tokenId, nftPrice, maturityDate);

        // lock asset nft
        registry.setApprovalForAll(SHELF, true);
        shelf.lock(loanId);

        // borrow loan with half of the creditline
        uint borrowAmount = reserve.totalBalance() + clerk.creditline() / 2;
        uint preMakerDebt = clerk.debt();

        borrowLoan(loanId, borrowAmount);

        // check debt increase in maker
        assertEqTol(clerk.debt(), preMakerDebt + (clerk.creditline() / 2) ,"clerk debt");

        // jump 5 days into the future
        hevm.warp(block.timestamp + 5 days);

        // repay entire loan debt
        uint debt = pile.debt(loanId);
        // repayment should reduce maker debt
        preMakerDebt = clerk.debt();
        repayLoan(loanId, debt);
        assertTrue(clerk.debt() < preMakerDebt);
    }

    // helper
    function assertHasPermissions(address con, address ward) public {
        uint perm = TAuth(con).wards(ward);
        assertEq(perm, 1);
    }

    function assertHasNoPermissions(address con, address ward) public {
        uint perm = TAuth(con).wards(ward);
        assertEq(perm, 0);
    }

    function assertMakerDebtReduced(uint preDebt, uint investmentAmount) public returns (uint wipeAmount) {
        if (preDebt > 1) {
            if (preDebt > investmentAmount) {
                assertEq(clerk.debt(), (preDebt - investmentAmount));
                return investmentAmount;
            } else {
                assertTrue(clerk.debt() <= 1);
                return preDebt;
            }
        }
        return 0;
    }

}
