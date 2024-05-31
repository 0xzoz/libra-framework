module diem_framework::test_reputation {
    //This file needs to extend testing to include changes 
    //and additions to libra-frameworks Sybil resistance mechanisms
    
    //For each of the features, they will need to be set in the tests as they are off by default untill added - see feature_flags.move. 
    //They are called in epoch_boundary

    //leaderboard.move tests
    
    //leaderboard increments on epoch changes for validators
    //leaderboard decrements on epoch changes for validators
    //leaderboard streak increments on multiple succesful epochs for a validator  


    //reputation.move tests
    
    //reputation points increase
    //reputation reverts to 0 if losses > 0 && losses > wins
    //reputation adds an extra point if score is greater than 7(one week of successive wins )
    //reputation adds an extra point if score is greater than 30(one month of successive wins)
    //reputation loses a point if the validator is not joining the set at an acceptable rate ((net_wins * 100) / ( wins + losses)) < 80
    //reputation decreases if consectutive jails is greater than 3
    //reputation decreases by 1 point if consecutive jails is greater that 30

    //vouch.move tests

    //a validator can not vouch after maximum number of vouches for a validator has been reached
    //a vouch expires after 45 epochs
    //GivenOut resource is initialized and is being populated for a validator
    //VouchTree resource is initialized and is being populated correctly for a validator
    

    //Go through vouch.move and find more tests that can be added and increase coverage
}
