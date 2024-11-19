# COMP 4901W Final Project

Final Project for **COMP 4901W: Introduction to Blockchain, Cryptocurrencies and Smart Contracts**

### IDE
Remix

### Notice
If there are any conflicts of interest or special concerns regarding this repository, please contact me.

### Existing Problems

- The casino can tamper with the RNG by signing up as several players and then deciding which subset of its hashes to reveal. It can decrypt all the revelations by the other players and thus knows the current status of r, when it has to decide whether to reveal or not.

- The contract allows the same value of k to be reused. So, when a bettor wins, they can make many more bets with the same k. The bettor_bet() is also vulnerable to frontrunning by the casino.

- Unbounded loop at line 341. If n_players is large enough, the gas usage will exceed even the maximum possible gas per block and this function can never be called successfully. Same issue at line 381.
