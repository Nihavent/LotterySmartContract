// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    // Events
    event EnteredRaffle(address indexed player);

    // Modifiers
    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }


    Raffle raffle;
    HelperConfig helperConfig;

    // State variables
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinatior;
    bytes32 gasLane; // key hash
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinatior,
            gasLane, // key hash
            subscriptionId,
            callbackGasLimit,
            link,
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitialisesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //* Enter Raffle Tests */
    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector); // expectRevert() is a foundry cheat 
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER); 
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() 
        public raffleEnteredAndTimePassed {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }


    //* Check Upkeep tests */
    function testChecksUpkeepReturnsTrueWhenRaffleIsOpen() public {
        // arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeeepReturnsFalseIfRaffleNotOpen() 
        public raffleEnteredAndTimePassed {
        // arrange - in modifier
        raffle.performUpkeep("");

        // act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // assert
        assert(upKeepNeeded == false);
    }

    // testCheckUpkeepReturnsFalseIfEnoughtimeHasntPassed
    function testCheckUpkeepReturnsFalseIfEnoughtimeHasntPassed() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        // act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // assert
        assert(upKeepNeeded == false);
    }

    // testCheckUpkeepReturnsTrueWhenParametersAreGood
    function testCheckUpkeepReturnsTrueWhenParametersAreGood() 
    public raffleEnteredAndTimePassed {
        // arrange - in modifier

        // act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // assert
        assert(upKeepNeeded == true);
    }

    //* Perform Upkeep tests */
    function testPeformUpkeepCanOnlyRunIfcheckUpkeepIsTrue() 
    public raffleEnteredAndTimePassed {
        // arrange - in modifier

        // act/assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        // act/assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState)
            );
        raffle.performUpkeep("");
    }

    // What if I need to test using the output of an event?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() 
        public raffleEnteredAndTimePassed {
        //arrange - in modifier
        // act
        vm.recordLogs();
        raffle.performUpkeep(""); //  Emits RequestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        // assert
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    //* Fulfill Random Words */

    modifier skipFork() {
        if (block.chainid != 31337){
            return;
        }
        _;
    }
    
    function testFulfillRandomWordsCanOnlyBetCalledAfterPerformUpkeep(uint256 randomRequestId) 
        public raffleEnteredAndTimePassed skipFork
    {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatior).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerandSendsMoney() 
        public raffleEnteredAndTimePassed skipFork
    {
        // arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for(uint256 i = startingIndex; 
            i < startingIndex + additionalEntrants; 
            i++){
            address player = address(uint160(i)); // generate address based on index of loop
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1); // expected prize won

        // act
        vm.recordLogs();
        raffle.performUpkeep(""); //  Emits RequestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimestamp = raffle.getLastTimestamp();

        // pretend to be chainlink VRF to get random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinatior).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimestamp < raffle.getLastTimestamp());
        console.log(raffle.getRecentWinner().balance);
        console.log(STARTING_USER_BALANCE + prize- entranceFee) ;
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
    }

}




