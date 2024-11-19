pragma solidity >=0.7.0 <0.9.0;

// TODO: check datatype
// TODO: check mapping
// TODO: check authority
// TODO: cases when the casino cheated
// TODO: accessibility
contract casino {
    /*
    * ############################################################
    * ******************** variables ********************
    * throughout the whole processes, assume uint128 fits all integer values and won't cause overflow

    * Assume the whole process of the bet is from 8 a.m. to 11 p.m., 15 hours in between.
    * 1 Schweizerlandish schilling = 0.01 ETH;
    * p = 0.5, the bet is won and you pay them 2 schillings / the bet is lost and you get to keep their schilling;
    * the players can obtain a small reward if they honestly contribute to generating the random number. say, 1000 gwei -> 0.0019 USD as retrieved online May 19. They would split the reward. If the casino puts more than 1000 gwei, the bettors would split the extra reward if the casino cheat;
    * the casino should have enough deposit to pay for cheating in all the bets, so we check the total deposit the bettor placed, by recording the number of bettors;
    * we also record the number of players, denoted as n, for checking the number of t, and splitting the reward
    * n=p*q. p,q are two large primes which are the secret key. the casino publishes its public key for GM system, for the secret sharing of the players' random number

    * two mappings are used to record the money picking-up states
    */

    // record the start time of the bet
    uint256 public immutable START_TIME;
    // the bettor puts down a deposit of 1 Schweizerlandish schilling
    uint256 public immutable DEPOSIT;
    // the players' small reward
    uint256 public immutable PLAYER_REWARD;
    // the casino's address
    address public immutable CASINO_ADDRESS;
    // public key of the authority
    address public immutable AUTHORITY_ADDRESS;
    // in step 3, the casino deposits a huge amount of money in the smart contract.
    uint256 public deposit_of_casino;
    // for checking the total deposit the bettor placed
    uint256 public number_of_bettors;
    uint256 public required_deposit;
    // the number of players
    uint256 public n_players;
    uint256 public n_honest_players;
    // if the casino cheated
    bool public casino_cheated;

    // GM crypto system
    uint128 public immutable CASINO_PK_X;
    uint128 public immutable CASINO_PK_N;
    uint128 public prime_p;
    uint128 public prime_q;
    uint16 public r;

    // record the bettors' random number k
    mapping(uint256 => uint16) public bettor_k;
    mapping(uint256 => uint16) public player_random;
    mapping(uint256 => uint128[]) public player_encrypted_random;
    mapping(uint256 => bytes32) public player_hashed_random;
    // record if they can picked up the money
    mapping(uint256 => uint256) public bettor_balance;
    mapping(uint256 => bool) public bettor_win;
    mapping(uint256 => bool) public bettor_can_pick_up;
    mapping(uint256 => bool) public player_can_pick_up;
    // mapping for looking up items
    mapping(uint256 => address) public player_list;
    mapping(uint256 => address) public bettor_list;
    // we require the casino to reveal the result of betting within 10 blocks, otherwise, we regard the bettor as won
    mapping(uint256 => uint256) public betting_blocknum;

    event announce_register(address player_addr, uint256 idx);
    event announce_result(uint256 idx, bool ifwin);
    event bettor_bet_waiting_for_result(uint256 idx, uint128 k);
    event betting_ends_reveal_r(uint128 r, uint128 p, uint128 q);
    event casino_cheated_announce();

    /*
     * ############################################################
     * ******************** constructor ********************
     */
    constructor(
        uint128 pk_n,
        uint128 pk_x,
        address authority_addr
    ) public payable {
        // the initial value the casino puts down is the reward for the players who contribute to generating the random number
        require(
            tx.origin == msg.sender,
            "the casino should be the one to deploy the contract"
        );
        require(
            msg.value > 1000 gwei,
            "the player reward should be at least 1000 gwei"
        );

        DEPOSIT = 0.01 ether;
        CASINO_ADDRESS = msg.sender;
        START_TIME = block.timestamp;
        AUTHORITY_ADDRESS = authority_addr;
        PLAYER_REWARD = msg.value;

        CASINO_PK_N = pk_n;
        CASINO_PK_X = pk_x;

        number_of_bettors = 0;
        required_deposit = PLAYER_REWARD;
    }

    /* 
        * ############################################################
        * ******************** RNG ********************

        * the players commit their hashed random number, and send the encrypted random number to the contract. 
        * It is required that the players computes the encrypted and hashed values off-chain, and then send them to the contract.
        ? The hashed value should be computed as hashed_random = keccak128(abi.encodePacked(encrypted_rand,player_address,nonce).
        * the casino computes the r off-chain, and then send the encrypted value to the contract.
    */
    function register_player(address player_addr) public {
        player_list[n_players] = player_addr;
        emit announce_register(player_addr, n_players);
        n_players += 1;
        player_list[n_players] = AUTHORITY_ADDRESS;
        emit announce_register(player_addr, n_players);
        n_players += 1;
    }

    function player_commit_hashed_rng(
        bytes32 hashed_random,
        uint256 idx
    ) public {
        // TODO: check attack
        require(
            block.timestamp < START_TIME + 20 minutes,
            "the players can only commit the hash values in the first 20 minutes"
        );
        require(player_list[idx] == msg.sender, "wrong player idx");
        require(
            player_hashed_random[idx] == 0,
            "the player can only contribute once in a bet"
        );
        player_hashed_random[idx] = hashed_random;
    }

    function player_commit_encrypted_rng(
        uint128[] memory encrypted_random,
        uint128 nonce,
        uint256 idx
    ) public {
        // TODO: check attack
        require(
            block.timestamp > START_TIME + 20 minutes,
            "the players should finish committing the encrypted values."
        );
        require(player_list[idx] == msg.sender, "wrong player idx");
        if (msg.sender == AUTHORITY_ADDRESS) {
            require(
                block.timestamp < START_TIME + 30 minutes,
                "It should be before the casino commits r. The authority can have a little bit more time, since it won't collude with the casino, and can avoid casino to chead"
            );
        } else {
            require(
                block.timestamp < START_TIME + 30 minutes,
                "It should be before the casino commits r."
            );
        }
        require(
            player_encrypted_random[idx].length == 0,
            "the player can only contribute once in a bet"
        );
        require(
            verify_player_hash(encrypted_random, nonce, idx),
            "the hash value that the player committed before is invalid!"
        );
        player_encrypted_random[idx] = encrypted_random;
        player_can_pick_up[idx] = true;
        // we assume there are at least 1 honest player
        n_honest_players += 1;
    }

    function verify_player_hash(
        uint128[] memory encrypted_rand,
        uint128 nonce,
        uint256 idx
    ) public returns (bool) {
        // to be called by all participants and the casino
        return
            player_hashed_random[idx] ==
            keccak256(
                abi.encodePacked(encrypted_rand, player_list[idx], nonce)
            );
    }

    /* 
        * ############################################################
        * ******************** deposit functions ********************

        * functions for the casino and bettors to deposit money
        * the casino should have enough deposit to pay for cheating in all the bets. If the deposit is not enough, you should stop accepting new bets unless the casino increases it.
    */

    function casino_deposit() public payable {
        // TODO: check attack
        require(
            msg.sender == CASINO_ADDRESS,
            "only the casino can call this function"
        );
        require(
            block.timestamp < START_TIME + 13 hours,
            "the casino can add deposit for allowing more bettors to come"
        );
        deposit_of_casino += msg.value;
    }

    function bettor_bet(uint16 k) public payable {
        // TODO: check attack
        require(
            block.timestamp > START_TIME + 1 hours,
            "the bettor can only bet after r is committed"
        );
        require(
            block.timestamp < START_TIME + 12 hours + 50 minutes,
            "the bettor can only bet within 12h50min since the game starts"
        );
        require(
            msg.value == DEPOSIT,
            "the bettor should put down a deposit of 1 Schweizerlandish schilling"
        );
        // this actually requires the casino to deposit first
        require(
            deposit_of_casino >= required_deposit + DEPOSIT,
            "not enough deposit! The casino should put down more!"
        );
        require(k >= 0, "the random number should be positive");
        // a bettor can only bet once
        require(
            bettor_list[number_of_bettors] == address(0),
            "the bettor can only bet once in a bet"
        );
        bettor_list[number_of_bettors] = msg.sender;
        bettor_can_pick_up[number_of_bettors] = false;
        required_deposit += DEPOSIT;
        bettor_k[number_of_bettors] = k;
        betting_blocknum[number_of_bettors] = block.number;
        emit bettor_bet_waiting_for_result(number_of_bettors, k);
        number_of_bettors += 1;
    }

    function check_win(bool ifwin, uint256 idx) public {
        //the casino returns the result whether it win
        require(msg.sender == CASINO_ADDRESS, "only the casino can call this");
        require(
            bettor_balance[idx] == DEPOSIT,
            "can only announce winning the bet once"
        );
        if (ifwin || block.number > betting_blocknum[idx] + 10) {
            bettor_balance[idx] = 2 * DEPOSIT;
            bettor_win[idx] = true;
            emit announce_result(idx, true);
        } else {
            bettor_balance[idx] = 0;
            bettor_win[idx] = false;
            emit announce_result(idx, false);
        }
        bettor_can_pick_up[idx] = true;
    }

    /*
     * ############################################################
     * ******************** unimplemented rand functions ********************
     */
    function srand(uint128 k) public {
        // skip the implementation
    }

    function rand() public pure returns (uint128) {
        // skip the implementation
        return 42;
    }

    /*
     * ############################################################
     * ******************** reveal functions ********************
     * the casino reveals r
     */
    function announce_r(uint16 r_value, uint128 p, uint128 q) public {
        require(
            msg.sender == CASINO_ADDRESS,
            "only the casino can call this function"
        );
        require(
            block.timestamp > START_TIME + 12 hours + 50 minutes,
            "the casino can only reveal r after the betting end"
        );
        require(
            block.timestamp < START_TIME + 13 hours,
            "the casino can only reveal r within 13 hours since the game starts"
        );
        r = r_value;
        prime_p = p;
        prime_q = q;
        emit betting_ends_reveal_r(r_value, p, q);
    }

    /*
     * ############################################################
     * ******************** casino calculate the plaintext of players ********************
     */

    function bitwise_qr_check(uint128 c) public returns (uint16) {
        require(
            block.timestamp > START_TIME + 13 hours,
            "too early, meaningless"
        );
        // check if c is QR mod p, and QR mod q
        bool qr_mod_q = (1 == c ** ((prime_p - 1) / 2) % prime_p);
        bool qr_mod_p = (1 == c ** ((prime_q - 1) / 2) % prime_q);
        if (qr_mod_q && qr_mod_p) {
            return 1;
        }
        return 0;
    }

    function decrypt_m(uint128[] memory encrypted_m) public returns (uint16) {
        require(
            block.timestamp > START_TIME + 13 hours,
            "too early, meaningless"
        );
        if (encrypted_m.length == 16) {
            uint16 result = 0;
            for (uint8 i = 0; i < encrypted_m.length; i++) {
                result |= bitwise_qr_check(encrypted_m[i]) << (15 - i);
            }
            return result;
        } else return uint16(0);
    }

    function reveal_all_m() public {
        require(
            block.timestamp > START_TIME + 13 hours,
            "too early, meaningless"
        );
        // one should have enough gas to call this function
        for (uint128 i = 0; i < n_players; i++) {
            player_random[i] = decrypt_m(player_encrypted_random[i]);
        }
    }

    /*
     * ############################################################
     * ******************** verifications ********************
     */
    function claim_cheated(uint256 idx) public {
        require(player_list[idx] == msg.sender, "you are not the player");
        require(
            block.timestamp > START_TIME + 13 hours,
            "the player can only claim cheated after 13 hours since the game starts"
        );
        require(
            block.timestamp < START_TIME + 15 hours,
            "the player can only claim cheated within 15 hours since the game starts"
        );
        uint16 submitted_r = plaintext_r();
        if (submitted_r != r) {
            emit casino_cheated_announce();
            casino_cheated = true;
        }
        srand(r + bettor_k[idx]);
        if (
            (rand() % 2 == 0 && bettor_win[idx] != true) ||
            (rand() % 2 == 1 && bettor_win[idx] != false)
        ) {
            emit casino_cheated_announce();
            casino_cheated = true;
        }
    }

    function plaintext_r() public returns (uint16) {
        require(
            block.timestamp > START_TIME + 13 hours,
            "too early, meaningless"
        );
        uint16 enc = 0;
        for (uint128 i = 0; i < n_players; i++) {
            enc ^= player_random[i];
        }
        return enc;
    }

    /*
        * ############################################################
        * ******************** pick up functions ********************

        * the players, bettor, casino pick up their money
    */
    function bettor_get_money(uint256 idx) public {
        require(
            block.timestamp < START_TIME + 15 hours,
            "the bettor can only get its money before the casino gets back its money"
        );
        require(
            block.timestamp > START_TIME + 1 hours,
            "it is meaningless to call this function before the bet starts"
        );
        require(bettor_list[idx] == msg.sender, "you are not the bettor");
        uint256 val = bettor_balance[idx];
        if (!casino_cheated) {
            require(
                bettor_can_pick_up[idx],
                "the bettor can only get its money when it is not locked. It is locked when the bettor is betting, or haven't bet."
            );
        } else {
            val += (deposit_of_casino - PLAYER_REWARD) / number_of_bettors;
        }
        bettor_can_pick_up[idx] = false;
        bettor_balance[idx] = 0;
        (bool success, ) = msg.sender.call{value: val}("");
        require(success);
    }

    function player_get_money(uint256 idx) public {
        // before a ddl, the player gets its own money
        require(
            block.timestamp < START_TIME + 15 hours,
            "the player can only get its money before the casino gets back its money"
        );
        // actually i think it is redundant
        require(
            block.timestamp > START_TIME + 1 hours,
            "it is meaningless to call this function before the bet starts"
        );
        require(player_list[idx] == msg.sender, "you are not the player");
        require(
            player_can_pick_up[idx],
            "the player can only get its money after it has contributed"
        );
        player_can_pick_up[idx] = false;
        (bool success, ) = msg.sender.call{
            value: PLAYER_REWARD / n_honest_players
        }("");
        if (!success) {
            player_can_pick_up[idx] = true;
        }
    }

    function casino_get_money() public {
        // the casino get its money after a certain deadline, in the end of the bet
        require(
            block.timestamp > START_TIME + 15 hours,
            "the casino can only get its money after the bet ends"
        );
        require(
            msg.sender == CASINO_ADDRESS,
            "only the casino can call this function"
        );
        // it does not matter how many times the function is called.
        msg.sender.call{value: address(this).balance}("");
    }
}
