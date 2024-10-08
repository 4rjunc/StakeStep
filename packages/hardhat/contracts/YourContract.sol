//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// Useful for debugging. Remove when deploying to a live network.
import "hardhat/console.sol";

// Use openzeppelin to inherit battle-tested implementations (ERC20, ERC721, etc)
// import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * A smart contract that allows changing a state variable of the contract and tracking the changes
 * It also allows the owner to withdraw the Ether in the contract
 * @author BuidlGuidl
 */
contract YourContract {
	// State Variables
	address public immutable owner;
	string public greeting = "StakeStep: build your habits";

  
 struct Task {
        bool completed;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
    }

    struct Challenge {
        address creator;
        uint256 stakeAmount;
        uint256 totalStaked;
        uint256 creationTime;
        uint256 durationInDays;
        string challengeName;
        string description;
        mapping(address => bool) participants;
        address[] participantList;
        mapping(address => mapping(uint256 => Task)) tasks;
        mapping(address => uint256) participantScores;
        bool fundsDistributed;
    }

    mapping(bytes32 => Challenge) public challenges;
    bytes32[] public challengeIds;
    
    event ChallengeCreated(bytes32 indexed challengeId, address creator, uint256 stakeAmount, uint256 durationInDays, string challengeName);
    event UserJoined(bytes32 indexed challengeId, address user);
    event TaskCompleted(bytes32 indexed challengeId, address user, uint256 day);
    event TaskVoted(bytes32 indexed challengeId, address voter, address participant, uint256 day, bool inFavor);
    event FundsRefunded(bytes32 indexed challengeId, address user, uint256 amount);// Events: a way to emit log statements from smart contract that can be listened to by external parties
    event AdditionalFundsDistributed(bytes32 indexed challengeId, address participant, uint256 amount);
	// Constructor: Called once on contract deployment
	// Check packages/hardhat/deploy/00_deploy_your_contract.ts
	constructor(address _owner) {
		owner = _owner;
	}

	// Modifier: used to define a set of rules that must be met before or after a function is executed
	// Check the withdraw() function
	modifier isOwner() {
		// msg.sender: predefined variable that represents address of the account that called the current function
		require(msg.sender == owner, "Not the Owner");
		_;
	}

   function createChallenge(
        bytes32 _challengeId,
        uint256 _durationInDays, 
        string memory _challengeName, 
        string memory _description
    ) external payable returns (bytes32) {
        require(msg.value > 0, "Must stake some ETH to create a challenge");
        require(_durationInDays > 0, "Duration must be greater than 0");
        require(challenges[_challengeId].creator == address(0), "Challenge ID already exists");
        
        Challenge storage newChallenge = challenges[_challengeId];
        newChallenge.creator = msg.sender;
        newChallenge.stakeAmount = msg.value;
        newChallenge.totalStaked = msg.value;
        newChallenge.creationTime = block.timestamp;
        newChallenge.durationInDays = _durationInDays;
        newChallenge.challengeName = _challengeName;
        newChallenge.description = _description;
        newChallenge.participants[msg.sender] = true;
        newChallenge.participantList.push(msg.sender);
        
        challengeIds.push(_challengeId);
        
        emit ChallengeCreated(_challengeId, msg.sender, msg.value, _durationInDays, _challengeName);
        return _challengeId;
    }

    function joinChallenge(bytes32 _challengeId) external payable {
        Challenge storage challenge = challenges[_challengeId];
        require(!challenge.participants[msg.sender], "Already joined this challenge");
        require(msg.value == challenge.stakeAmount, "Must stake exact amount");
        require(block.timestamp < challenge.creationTime + challenge.durationInDays * 1 days, "Challenge has ended");

        challenge.participants[msg.sender] = true;
        challenge.participantList.push(msg.sender);
        challenge.totalStaked += msg.value;
        emit UserJoined(_challengeId, msg.sender);
    }

function voteOnTask(bytes32 _challengeId, address _participant, uint256 _day, bool _inFavor) external {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.participants[msg.sender], "Only participants can vote");
        require(_day < challenge.durationInDays, "Invalid day");
        require(!challenge.tasks[_participant][_day].hasVoted[msg.sender], "Already voted");

        Task storage task = challenge.tasks[_participant][_day];
        task.hasVoted[msg.sender] = true;

        if (_inFavor) {
            task.votesFor++;
        } else {
            task.votesAgainst++;
        }

        if (task.votesFor > challenge.participantList.length / 2) {
            task.completed = true;
            emit TaskCompleted(_challengeId, _participant, _day);
        }

        emit TaskVoted(_challengeId, msg.sender, _participant, _day, _inFavor);
    }

    
    function claimRefund(bytes32 _challengeId) external {
      Challenge storage challenge = challenges[_challengeId];
      require(challenge.participants[msg.sender], "Not a participant");
      require(block.timestamp >= challenge.creationTime + challenge.durationInDays * 1 days, "Challenge not ended");

      uint256 completedTasks = 0;
      for (uint256 i = 0; i < challenge.durationInDays; i++) {
          if (challenge.tasks[msg.sender][i].completed) {
              completedTasks++;
          }
      }

      uint256 refundAmount = (challenge.stakeAmount * completedTasks) / challenge.durationInDays;
      challenge.participants[msg.sender] = false;
      challenge.totalStaked -= challenge.stakeAmount;

      // Update the participant's score
      challenge.participantScores[msg.sender] = completedTasks;

      payable(msg.sender).transfer(refundAmount);
      emit FundsRefunded(_challengeId, msg.sender, refundAmount);
  }

  function distributeRemainingFunds(bytes32 _challengeId) external {
      Challenge storage challenge = challenges[_challengeId];
      require(block.timestamp >= challenge.creationTime + challenge.durationInDays * 1 days + 7 days, "Wait period not over");
      require(!challenge.fundsDistributed, "Funds already distributed");

      uint256 remainingFunds = address(this).balance;
      require(remainingFunds > 0, "No funds to distribute");

      uint256 totalScore = 0;
      uint256 highestScore = 0;
      uint256 topPerformersCount = 0;

      // Calculate total score and find highest score
      for (uint256 i = 0; i < challenge.participantList.length; i++) {
          address participant = challenge.participantList[i];
          uint256 score = challenge.participantScores[participant];
          totalScore += score;
          if (score > highestScore) {
              highestScore = score;
              topPerformersCount = 1;
          } else if (score == highestScore) {
              topPerformersCount++;
          }
      }

      // Distribute funds to top performers
      uint256 distributionPerTopPerformer = remainingFunds / topPerformersCount;
      for (uint256 i = 0; i < challenge.participantList.length; i++) {
          address participant = challenge.participantList[i];
          if (challenge.participantScores[participant] == highestScore) {
              payable(participant).transfer(distributionPerTopPerformer);
              emit AdditionalFundsDistributed(_challengeId, participant, distributionPerTopPerformer);
          }
      }

      challenge.fundsDistributed = true;
}

    function getAllChallenges() external view returns (bytes32[] memory) {
        return challengeIds;
    }

    function getChallengeCount() external view returns (uint256) {
        return challengeIds.length;
    }

    function getChallengeInfo(bytes32 _challengeId) external view returns (
        address creator,
        uint256 stakeAmount,
        uint256 totalStaked,
        uint256 creationTime,
        uint256 durationInDays,
        uint256 participantCount,
        string memory challengeName,
        string memory description
    ) {
        Challenge storage challenge = challenges[_challengeId];
        return (
            challenge.creator,
            challenge.stakeAmount,
            challenge.totalStaked,
            challenge.creationTime,
            challenge.durationInDays,
            challenge.participantList.length,
            challenge.challengeName,
            challenge.description
        );
    }

    function getParticipants(bytes32 _challengeId) external view returns (address[] memory) {
        return challenges[_challengeId].participantList;
    }

    function getTaskStatus(bytes32 _challengeId, address _participant, uint256 _day) external view returns (
        bool completed,
        uint256 votesFor,
        uint256 votesAgainst
    ) {
        Task storage task = challenges[_challengeId].tasks[_participant][_day];
        return (task.completed, task.votesFor, task.votesAgainst);
    }  /**
	 * Function that allows the owner to withdraw all the Ether in the contract
	 * The function can only be called by the owner of the contract as defined by the isOwner modifier
	 */
	// function withdraw() public isOwner {
	// 	(bool success, ) = owner.call{ value: address(this).balance }("");
	// 	require(success, "Failed to send Ether");
	// }
	//
	/**
	 * Function that allows the contract to receive ETH
	 */
	receive() external payable {}
}
