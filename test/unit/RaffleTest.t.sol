//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// import {console} from "lib/forge-std/console.sol";
// import {Test} from "forge-std/Test.sol";
import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";    
import {Raffle} from "src/Raffle.sol";    
import {HelperConfig} from "script/HelperConfig.s.sol";   
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from  "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is CodeConstants, Test {
    Raffle public raffle;
    HelperConfig public helperConfig;
 
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;


    // test user
    address public PLAYER = makeAddr("player"); // "makeAddr" is a foundry cheat code
    uint256 public constant  STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig)= deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId; 
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);        
    }

    function testRaffleInitializesInOpenState() public view{
        // console.log(raffle.getRaffleState());

        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        // OR:
        // assert(uint256(raffle.getRaffleState()) == 1); 
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__SendMoreToEnterToRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordPlayersWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }
    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);

        // Act
        // event RaffleEntered(address indexed player);
        vm.expectEmit(true, false, false, false, address(raffle)); // 1 indexed parameters(1st true); no non-indexed - last false
        emit RaffleEntered(PLAYER);

        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }
    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act // Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();       

    }

//========== CHECK UPKEEP ===========
    function testCheckUpkeepReturnsFalseIfHasNoBalance() public {
                // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act 
        (bool upkeepNeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeded);    
        
    }


    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
                // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act 
        (bool upkeepNeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeded);
    }


    function testPerformUpkkepCanOnlyRunIfCheckUpkeepIsTrue() public {
                // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act 
        // Assert
        raffle.performUpkeep("");

    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();


        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers =  1;

        // Act //Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
            );

        raffle.performUpkeep("");
    }


    modifier raffleEntered() {
            vm.prank(PLAYER);
            raffle.enterRaffle{value: entranceFee}();
            vm.warp(block.timestamp + interval + 1);
            vm.roll(block.number + 1);
            _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered{

        // Act 
        vm.recordLogs();// whatever log is emmited - keep track and save into array
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
//================
        // From Vm.sol /topics are indexed parameters in the event; the data – combination of all other events/:
    /// An Ethereum log. Returned by `getRecordedLogs`.
    // struct Log {
    //     // The topics of the log, including the signature, if any.
    //     bytes32[] topics; 
    //     // The raw data of the log.
    //     bytes data;
    //     // The address of the log's emitter.
    //     address emitter;
    // }
//================
        bytes32 requestId = entries[1].topics[1];// The 1st log is from VRF, We need [1]; topics[0] is reserved

        //Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);

    }

// =========  FULFIL RANDOMWORDS =========

    modifier skipFork(){
        if(block.chainid != LOCAL_CHAIN_ID){
            return;            
        }
        _;
    }

    function testFulfillrandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork{
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));        
    } 


    function testFulfillrandomWordsPicksWinnerResetsAndSendsMoney() public raffleEntered skipFork{
        // Arrange
        uint256 additionalEntrants = 3; //total 4
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalcnce = expectedWinner.balance;

        // Act
        vm.recordLogs();// whatever log is emmited - keep track and save into array
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];// The 1st log is from VRF, We need [1]; topics[0] is reserved
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntrants+1);

        assert(recentWinner == expectedWinner);
        assert(winnerBalance == winnerStartingBalcnce + prize);
        assert(uint256(raffleState) == 0);
        assert(endingTimeStamp>startingTimeStamp);
    }

}