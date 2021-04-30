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
    IAssessor assessor;
    IOperator junior;
    IOperator senior;
    ICoordinator coordinator;
    INavFeed nav;
    IShelf shelf;
    IPile pile;
    IReserve reserve;
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
        nav = INavFeed(FEED);
        shelf = IShelf(SHELF);
        pile = IPile(PILE);
        assessor = IAssessor(ASSESSOR);
        senior = IOperator(SENIOR_OPERATOR);
        junior = IOperator(JUNIOR_OPERATOR);
        coordinator = ICoordinator(COORDINATOR);
        reserve = IReserve(RESERVE);
        tin = ERC20Like(JUNIOR_TOKEN);
        drop = ERC20Like(SENIOR_TOKEN);
        dai = ERC20Like(TINLAKE_CURRENCY);
        registry = new Title("TEST", "TEST");

        // cheat: give testContract permissions on root contract by overriding storage
        // storage slot for permissions => keccak256(key, mapslot) (mapslot = 0)
        hevm.store(ROOT_CONTRACT, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

        // todo fetch current block timestamp from chain
        // 21. April 2020
        hevm.warp(1619791388 + 2 days);
    }

    function investTranches() public {
        // pre invest state
        uint preReserveDaiBalance = dai.balanceOf(RESERVE);

        // whitelist self for tin & drop
        root.relyContract(SENIOR_MEMBERLIST, self);
        root.relyContract(JUNIOR_MEMBERLIST, self);

        IMemberList(SENIOR_MEMBERLIST).updateMember(self, uint(- 1));
        IMemberList(JUNIOR_MEMBERLIST).updateMember(self, uint(- 1));

        // get supe r powers on DAI contract
        hevm.store(TINLAKE_CURRENCY, keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));

        // mint DAI
        uint totalInvest = 12 ether;
        dai.mint(self, totalInvest);

        uint seniorInvest = 10 ether;
        uint juniorInvest = totalInvest - seniorInvest;

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
        uint tinPrice = assessor.calcJuniorTokenPrice(nav.approximatedNAV(), reserve.totalBalance());
        uint dropPrice = assessor.calcSeniorTokenPrice(nav.approximatedNAV(), reserve.totalBalance());
        uint tinExpected = rdiv(juniorInvest, tinPrice);
        uint dropExpected = rdiv(seniorInvest, dropPrice);

        // check correct tin & drop token received
        assertEqTol(tin.balanceOf(self), tinExpected, "rpc#1");
        assertEqTol(drop.balanceOf(self), dropExpected, "rpc#2");

    }


    function appraiseNFT(uint tokenId, uint nftPrice, uint maturityDate) public {
        root.relyContract(FEED, self);
        bytes32 nftId = keccak256(abi.encodePacked(address(registry), tokenId));
        nav.update(nftId, nftPrice, 0);
        nav.file("maturityDate", nftId, maturityDate);
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

    function testLoanCycle() public {
        root.relyContract(address(assessor), address(this));
        assessor.file("maxReserve", 1000000000000 * 1 ether);

        investTranches();

        // issue nft
        uint tokenId = registry.issue(self);
        // issue loan
        uint loanId = shelf.issue(address(registry), tokenId);

        // appraise nft
        uint totalAvailable = reserve.totalBalance();
        uint nftPrice = totalAvailable * 2;
        uint maturityDate = now + 2 weeks;
        appraiseNFT(tokenId, nftPrice, maturityDate);

        // lock asset nft
        registry.setApprovalForAll(SHELF, true);
        shelf.lock(loanId);
        // get loan ceiling
        uint ceiling = (nav.ceiling(loanId));

        // borrow loan with half of the reserve
        uint borrowAmount = totalAvailable/2;
        borrowLoan(loanId, borrowAmount);

        // jump 5 days into the future
        hevm.warp(now + 5 days);

        // repay entire loan debt
        uint debt = pile.debt(loanId);

        uint preReserve = reserve.totalBalance();
        repayLoan(loanId, debt);
        assertEqTol(reserve.totalBalance(),preReserve+debt, "rpc#repay");
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



}
