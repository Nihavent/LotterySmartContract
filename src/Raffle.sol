// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title A sample raffle contract
 * @author Nicholas Taylor
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {

    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    //** Type Declarations */
    enum RaffleState {
        OPEN,           // 0
        CALCULATING     // 1
    }

    //** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    
    uint256 private immutable i_entranceFee;
    // Duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //** Events */
    event EnteredRaffle(
        address indexed player
    );
    event PickedWinner(
        address indexed winner
    );

    constructor(uint256 entranceFee, 
                uint256 interval, 
                address vrfCoordinatior,
                bytes32 gasLane, // key hash
                uint64 subscriptionId,
                uint32 callbackGasLimit
                ) VRFConsumerBaseV2(vrfCoordinatior) { // The parent contract has a constructor, so we also need to pass the vrfCoordinatior address
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatior);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        
        s_raffleState = RaffleState.OPEN;
        //Set initial timestamp when lottery is deployed
        s_lastTimestamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // Check the amount of ETGH sent is at least equal to the entrance fee
        if(msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        // Check that the raffle state is currently open
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        // Add address of player to list of players
        s_players.push(payable(msg.sender));

        // After updating a storage variable, emit an event
        emit EnteredRaffle(msg.sender);
    }
    
    // When is the winner supposed to be picked?
    /**
     * @dev This is the function that Chailink Automation nodes call toks ee if it's time to perform an upkeep.checkupkeep
     * The following should be true for this function to return true:
     *  1. The time interval has passed between raffles
     *  2. The raffle is in the OPEN state
     *  3. The contract has ETG (aka players)
     *  4. The subscription is funded with LINK
     */

    function checkUpkeep(bytes memory /*checkData */) public view 
        returns (bool upkeepNeeded, bytes memory /*performData */) {
        // Check to see if enough time has passed
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        
        return(upkeepNeeded, "0x0");
    }

    // 1. Get a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING; // Set state of raffle to calculating
        // 2. Request the RNG tx1 
        // Will revert if subscription is not set and funded.
        i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // ID with funded LINK
            REQUEST_CONFIRMATIONS, // # of block confirmations required
            i_callbackGasLimit, // max gas limit the callback function can spend
            NUM_WORDS // Number of random numbers requested
        );
    }

    // 3. Get a random number from callback function
    function fulfillRandomWords(
        uint256 /*requestId*/ , 
        uint256[] memory randomWords
    ) internal override {
        // Pick random winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN; // Set state of raffle to calculating

        s_players = new address payable[](0); // Reset the players array
        s_lastTimestamp = block.timestamp; // Reset last block timestamp because we just concluded a round

        emit PickedWinner(winner); // Emit winner to logs

        //Pay the winner the entire balance of the contract
        (bool success, ) = s_recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }

        
    }

    /** Getting Functions */
    function getEntranceFee() external view returns(uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState){
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns(address) {
        return s_players[indexOfPlayer];
    }

}