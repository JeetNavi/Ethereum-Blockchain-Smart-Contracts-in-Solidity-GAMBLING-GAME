// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract s1960565 {
    
    address public playerA;
    address public playerB;
    address private owner;

    enum gameState {EmptyState, WaitingState, FullState, ReavealedState}
    //EmptyState - No players are in a game. Someone should call openGame().
    //WaitingState - One player has committed into a game. Someone else should call joinGame().
    //FullState - Two players are committed into a game. They should both proceed to call reveal().
    //RevealedState - Both players have revealed their random value. They should both proceed to call playGame().

    gameState public state; // Defaults to EmptyState.

    mapping(address => uint256) private playersBalances;
    mapping (address => Commit) private commits;

    bool public A_played;
    bool public B_played;
    bytes32 private A_randomValue;
    bytes32 private B_randomValue;

    uint public timeout = 2**256 - 1;

    struct Commit {
        bytes32 commit;
        bool revealed;
    }

    constructor(){   
        owner = msg.sender;
    }

    //Helper function
    function valueCheck(uint256 msgVal, address msgSender) public payable {
        //If sender has 3 ether already in "bank" balance, they can use this.
        if (playersBalances[msgSender] >= 3.1 ether){
            require(msgVal >= 10, "10 Wei is the minimum value - for contract profit.");
        //Else they need to deposit ether such that they will have atleast 3 ether in their "bank" balance.
        } else {
            require(msgVal >= (3.1 ether - playersBalances[msgSender] + 10), "Atleast 3.1 Ether is needed in bank balance to participate.");
        }
        playersBalances[msgSender] += msgVal - 10;
    }

    modifier onlyState(gameState expectedState) {
        require(state == expectedState, "Game state is not in correct state for this function to be called.");
        _;
    }

    modifier onlyPlayers {
        require(msg.sender == playerA || msg.sender == playerB, "Only players of the current game can call this function.");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    function openGame(bytes32 randomValAddrHash) public payable onlyState(gameState.EmptyState) {
        valueCheck(msg.value, msg.sender);
        commits[msg.sender].commit = randomValAddrHash; //No notion of a value check here so it is not in the valueCheck function.
        commits[msg.sender].revealed = false;
        playerA = msg.sender;
        state = gameState.WaitingState;
    }

    function joinGame(bytes32 randomValAddrHash) public payable onlyState(gameState.WaitingState) {
        require(!(msg.sender == playerA), "You can't join a game with yourself");
        valueCheck(msg.value, msg.sender);
        commits[msg.sender].commit = randomValAddrHash; //No notion of a value check here so it is not in the valueCheck function.
        commits[msg.sender].revealed = false;
        playerB = msg.sender;
        state = gameState.FullState;
    }

    function reveal(bytes32 randomValue) public onlyPlayers onlyState(gameState.FullState) {
        require(commits[msg.sender].revealed == false, "You have already revealed!");
        require(commits[msg.sender].commit == keccak256(abi.encodePacked(randomValue, msg.sender)), "Revealed random number hashed with your address does not match with commit");
        if (msg.sender == playerA) {
            A_randomValue = randomValue;
            commits[playerA].revealed = true;
            timeout = 2**256 - 1; // Incase owner started stale game timer
        } else {
            B_randomValue = randomValue;
            commits[playerB].revealed = true;
            timeout = 2**256 - 1;
        }

        if (commits[playerA].revealed == true && commits[playerB].revealed == true){
            state = gameState.ReavealedState;
        }
    }

    function playGame() public payable onlyPlayers onlyState(gameState.ReavealedState) returns (uint256){
        if (msg.sender == playerA){
            require (!A_played, "You have already played!");
            A_played = true;
        } else {
            require (!B_played, "You have already played!");
            B_played = true;
        }

        timeout = 2**256 - 1; // In case there was a timer initiated in waitingState or if owner started timer
        uint256 random_number = (uint(A_randomValue ^ B_randomValue) % 6) + 1;

        bool A_win;

        if (random_number <= 3) {
            A_win = true;
        } else {
            A_win = false;
        }
        
        if (msg.sender == playerB && !A_win){
            playersBalances[playerA] -= (((random_number - 3) * 10**18) - 10); // -10 because remember 10 wei was put into contract profits.
            playersBalances[playerB] += (((random_number - 3) * 10**18) - 10);
        } else if (msg.sender == playerA && A_win){
            playersBalances[playerB] -= (((random_number) * 10**18) - 10);
            playersBalances[playerA] += (((random_number) * 10**18) - 10);
        }

        if (!A_played || !B_played){
                timeout = block.timestamp + 120; // 2 minutes timout interval - only for owner to use
        }

        //Setting state variables to default values once game is over.
        if (A_played && B_played){
            A_played = false;
            B_played = false;
            playerA = address(0);
            playerB = address(0);
            state = gameState.EmptyState;
        }

        return random_number;
    }

    //Functions for balance operations:

    function withdraw() public payable{
        require(!(msg.sender == playerA || msg.sender == playerB), "You cannot withdraw while in a game"); // To ensure players in a game that is not over cannot withdraw.
        uint256 b = playersBalances[msg.sender];
        playersBalances[msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: b}("");
        require(sent, "Failed to withdraw Ether");
    }

    function getBalance() public view returns (uint256){
        return playersBalances[msg.sender];
    }

    //Timeout functions to follow. These are to ensure nobody can avoid paying gas to play (because they know they have lost), 
    //Or to avoid two adversarial players
    //causing a stale game, i.e. a game that never ends and enables a DoS on the contract.

    function startRevealTimeout() public onlyPlayers onlyState(gameState.FullState){
        require(commits[msg.sender].revealed == true, "You can't start this timer because you haven't revealed yet.") ;
        timeout = block.timestamp + 120; // 2 minutes timout interval
    }

    function claimRevealTimout() public onlyPlayers onlyState(gameState.FullState){
        require(commits[msg.sender].revealed == true, "You are the player who is the facing timeout timer!") ;
        require(block.timestamp >= timeout, "Timeout timer either not started yet or not finished yet.");

        if (msg.sender == playerA) {
            playersBalances[playerB] -= ((3.1 ether) - 10); //0.1 ether penalty for not revealing! To avoid players from avoiding gas costs because they may already know outcome.
            playersBalances[playerA] += ((3.1 ether) - 10);
        } else {
            playersBalances[playerA] -= ((3.1 ether) - 10);
            playersBalances[playerB] += ((3.1 ether) - 10);
        }

        playerA = address(0);
        playerB = address(0);
        state = gameState.EmptyState;
        timeout = 2**256 - 1;
    }

    function ownerClaimPlayTimeout() public payable onlyOwner onlyState(gameState.ReavealedState) {
        require(block.timestamp >= timeout, "Timeout timer either not started yet or not finished yet.");
        if (!A_played) {
            playersBalances[playerA] -= (0.1 ether) - 10; //0.1 ether penalty for not playing game - goes to contract balance (i.e. no player will have this 0.1 eth).
        } else {
            playersBalances[playerB] -= (0.1 ether) - 10;
        }
        timeout = 2**256 - 1;
        A_played = false;
        B_played = false;
        playerA = address(0);
        playerB = address(0);
        state = gameState.EmptyState;
    }

    function ownerResetStaleGameTimer() public payable onlyOwner {
        require(state == gameState.FullState || state == gameState.ReavealedState, "Game is not in expected state for this function.");
        if (state == gameState.FullState) {
            require(commits[playerA].revealed == false && commits[playerB].revealed == false, "Game is not in a stale condition!");
        } else {
            require(!A_played && !B_played, "Game is not in a stale condition!");
        }
        timeout = block.timestamp + 300;
        }
    
    function ownerResetStaleGame() public payable onlyOwner {
        require(state == gameState.FullState || state == gameState.ReavealedState, "Game is not in expected state for this function.");
        require(block.timestamp >= timeout, "Timeout timer either not started yet or not finished yet.");
        //No further checks required - by logic of code it is garunteed that game is in the SAME stale state
        //Because we reset timout variable in each new game state. 
        
        // Both players will lose their deposited 3.1 eth and the game restarts.
        playersBalances[playerA] -= (3.1 ether) - 10; // Remains in contract balance i.e. goes to contract balance.
        playersBalances[playerB] -= (3.1 ether) - 10;
        timeout = 2**256 - 1;
        playerA = address(0);
        playerB = address(0);
        state = gameState.EmptyState;
    }
}