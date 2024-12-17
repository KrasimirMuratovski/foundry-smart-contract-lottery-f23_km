//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/console.sol";

/**
* @title
* @author
* @notice
* @dev Implements Chainlink VRFv2.5 

*/

contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreToEnterToRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /*  Type Declarations */
    enum RaffleState {
        OPEN, // Can be converted to int - 0
        CALCULATING //1
    }


    /*  State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS= 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players; // payable  - whoever wins must be able to pay to
    uint256 private s_lastTimeStamp;
    address private s_recentWinner; // payable  - whoever wins must be able to pay to
    RaffleState private s_raffleState;



    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);


    constructor(uint256 entranceFee,uint256 interval,address vrfCoordinator, bytes32 gasLane, uint256 subscriptionId, uint32 callbackGasLimit) 
    VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        console.log("HELLO!!!");
        console.log(msg.value);
        // 1st ver: require(msg.value >=i_entranceFee, "Not enough ETH");//costs a lot of gas to save as a string
        // 3rd ver: require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterToRaffle()); //Newest, and only possible if compiled with 0.8.19 and less gas efficient than 2
        if (msg.value < i_entranceFee) {
            //2nd ver
            revert Raffle__SendMoreToEnterToRaffle();
        }
        
        if (s_raffleState!= RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }
        
    // https://docs.chain.link/chainlink-automation/guides/compatible-contracts

    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);//the time between raffles has passed
        bool isOpen = (s_raffleState == RaffleState.OPEN);// the raffle is open
        bool hasBalance = (address(this).balance > 0);// contract has balance
        bool hasPlayers = (s_players.length > 0);
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded,"");

    }

    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        //check  if enough time passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded){
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));    
        }

        s_raffleState = RaffleState.CALCULATING;

                //https://docs.chain.link/vrf/v2-5/getting-started
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient// name of the contract VRFV2PlusClient, the name of the struct RandomWordsRequest
            .RandomWordsRequest({
                keyHash: i_keyHash,//The gas lane key hash value, which is the maximum gas price you are willing to pay for a request in wei. 
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,//The limit for how much gas to use for the callback request to your contract's 
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

//   function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;
// Virtual function in the parrent class
    function fulfillRandomWords(uint256 /* requestId */,uint256[] calldata randomWords) internal virtual override {
        // s_player =10
        // rng = 18541651651516541
        // 12%10=2 -> winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if(!success){
            revert Raffle__TransferFailed();
        }

    }

    /** Getter functions*/
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    } //getEntranceFee


    function getRaffleState() external view returns(RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns(address){
        return s_players[indexOfPlayer];
    }

    function getLastTimestamp() external view returns(uint256){
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns(address){
        return s_recentWinner;
    }



}

