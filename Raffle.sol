//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

/**
* @title
* @author
* @notice
* @dev Implements Chainlink VRFv2.5 

*/

contract Raffle {
    /* Errors */
    error Raffle__SendMoreToEnterToRaffle();

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;

    address payable[] private s_players; // payable  - whoever wins must be able to pay to

    /* Events */
    event RaffleEntered(address indexed player);

    constructor(uint256 entranceFee, uint256 interval) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // 1st ver: require(msg.value >=i_entranceFee, "Not enough ETH");//costs a lot of gas to save as a string
        // 3rd ver: require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterToRaffle()); //Newest, and only possible if compiled with 0.8.19 and less gas efficient than 2
        if (msg.value < i_entranceFee) {
            //2nd ver
            revert Raffle__SendMoreToEnterToRaffle();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    // 1. Get a random number
    // 2. Use random number to pick a player
    // 3. Be automatically called

    function pickWinner() external {
        //check  if enough time passed
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert();
        }

        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    /** Getter functions*/
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    } //getEntranceFee
}
