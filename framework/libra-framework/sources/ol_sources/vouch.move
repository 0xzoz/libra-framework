
module ol_framework::vouch {
    use std::signer;
    use std::vector;
    use std::error;
    use ol_framework::ancestry;
    use ol_framework::ol_account;
    use ol_framework::epoch_helper;

    use diem_framework::account;
    use diem_framework::system_addresses;
    use diem_framework::transaction_fee;

    friend diem_framework::genesis;
    friend ol_framework::validator_universe;
    friend ol_framework::proof_of_fee;
    friend ol_framework::jail;
    friend ol_framework::epoch_boundary;

    #[test_only]
    friend ol_framework::mock;
    #[test_only]
    friend ol_framework::test_pof;

    /// Maximum number of vouches
    const MAX_VOUCHES: u64 = 3;

    /// Limit reached. You cannot give any new vouches.
    const EMAX_LIMIT_GIVEN: u64 = 4;

    /// trying to vouch for yourself?
    const ETRY_SELF_VOUCH_REALLY: u64 = 1;

    /// how many epochs must pass before the voucher expires.
    const EXPIRATION_ELAPSED_EPOCHS: u64 = 90;

    /// Struct for the Voucher
    /// Alice vouches for Bob
    struct GivenOut has key {
      /// list of the accounts I'm vouching for
      vouches_given: vector<address>,
      /// maximum number of vouches that can be given
      limit: u64,
    }

    /// Struct for the Vouchee
    /// Vouches received from other people
    /// keeps a list of my buddies and when the vouch was given.
    // TODO: someday this should be renamed to Received
    struct MyVouches has key {
      my_buddies: vector<address>,
      epoch_vouched: vector<u64>,
    }



    // init the struct on a validators account.
    public(friend) fun init(new_account_sig: &signer ) {
      let acc = signer::address_of(new_account_sig);

      if (!exists<MyVouches>(acc)) {
        move_to<MyVouches>(new_account_sig, MyVouches {
          my_buddies: vector::empty(),
          epoch_vouched: vector::empty(),
        });
      };
      // Note: separate initialization for migrations of accounts which already
      // have MyVouches
      if(!exists<GivenOut>(acc)){
        move_to<GivenOut>(new_account_sig, GivenOut {
          vouches_given: vector::empty(),
          limit: 0,
        });
      }
    }


    #[view]
    // NOTE: this should be renamed to is_received_init()
    public fun is_init(acc: address ):bool {
      exists<MyVouches>(acc)
    }

    // implement the vouching.
    fun vouch_impl(give_sig: &signer, receive: address) acquires MyVouches, GivenOut {
      let give_acc = signer::address_of(give_sig);
      assert!(give_acc != receive, error::invalid_argument(ETRY_SELF_VOUCH_REALLY));
      assert!(check_can_add(give_acc), error::invalid_state(EMAX_LIMIT_GIVEN));

      if (!exists<MyVouches>(receive)) return;
      let epoch = epoch_helper::get_current_epoch();
      // this fee is paid to the system, cannot be reclaimed
      let c = ol_account::withdraw(give_sig, vouch_cost_microlibra());
      transaction_fee::user_pay_fee(give_sig, c);

      let v = borrow_global_mut<MyVouches>(receive);

      let (found, i) = vector::index_of(&v.my_buddies, &give_acc);
      if (found) { // prevent duplicates
        // update date
        let e = vector::borrow_mut(&mut v.epoch_vouched, i);
        *e = epoch;
      } else {
        // limit amount of vouches given to 3
        vector::insert(&mut v.my_buddies, 0, give_acc);
        vector::insert(&mut v.epoch_vouched, 0, epoch);

        trim_vouches(v)
      }
    }

    fun check_can_add(giver: address): bool acquires GivenOut{
      if (!exists<GivenOut>(giver)) return false;

      let state = borrow_global<GivenOut>(giver);
      vector::length(&state.vouches_given) < state.limit
    }

    /// ensures no vouch list is greater than
    /// hygiene for the vouch list
    public (friend) fun root_trim_vouchers(framework: &signer, acc: &address) acquires MyVouches {
      system_addresses::assert_ol(framework);
          // limit amount of vouches given to 3
      let state = borrow_global_mut<MyVouches>(*acc);
      trim_vouches(state)
    }

    // safely trims vouch list, drops backmost elements
    fun trim_vouches(state: &mut MyVouches) {
        if (vector::length(&state.my_buddies) >= MAX_VOUCHES) {
          vector::trim(&mut state.my_buddies, MAX_VOUCHES - 1);
        };
        if (vector::length(&state.epoch_vouched) > MAX_VOUCHES) {
          vector::trim(&mut state.epoch_vouched, MAX_VOUCHES - 1);
        }
    }

    /// will only succesfully vouch if the two are not related by ancestry
    /// prevents spending a vouch that would not be counted.
    /// to add a vouch and ignore this check use insist_vouch
    public entry fun vouch_for(give_sig: &signer, receive: address) acquires MyVouches, GivenOut {
      ancestry::assert_unrelated(signer::address_of(give_sig), receive);
      vouch_impl(give_sig, receive);
    }

    /// you may want to add people who are related to you
    /// there are no known use cases for this at the moment.
    public entry fun insist_vouch_for(give_sig: &signer, receive: address) acquires MyVouches, GivenOut {
      vouch_impl(give_sig, receive);
    }

    /// Let's break up with this account
    public entry fun revoke(give_sig: &signer, its_not_me_its_you: address) acquires MyVouches {
      let give_acc = signer::address_of(give_sig);
      assert!(give_acc!=its_not_me_its_you, ETRY_SELF_VOUCH_REALLY);

      if (!exists<MyVouches>(its_not_me_its_you)) return;

      let v = borrow_global_mut<MyVouches>(its_not_me_its_you);
      let (found, i) = vector::index_of(&v.my_buddies, &give_acc);
      if (found) {
        vector::remove(&mut v.my_buddies, i);
        vector::remove(&mut v.epoch_vouched, i);
      };
    }

    /// If we need to reset a vouch list for genesis and upgrades
    public(friend) fun vm_migrate(vm: &signer, val: address, buddy_list: vector<address>) acquires MyVouches {
      system_addresses::assert_ol(vm);
      bulk_set(val, buddy_list);
    }

    // implements bulk setting of vouchers
    fun bulk_set(receiver_acc: address, buddy_list: vector<address>) acquires MyVouches {

      if (!exists<MyVouches>(receiver_acc)) return;

      let v = borrow_global_mut<MyVouches>(receiver_acc);

      // take self out of list
      let (is_found, i) = vector::index_of(&buddy_list, &receiver_acc);

      if (is_found) {
        vector::swap_remove<address>(&mut buddy_list, i);
      };

      v.my_buddies = buddy_list;

      let epoch_data: vector<u64> = vector::map_ref(&buddy_list, |_e| { 0u64 } );
      v.epoch_vouched = epoch_data;
    }

    #[view]
    /// gets all buddies, including expired ones
    public fun all_vouchers(val: address): vector<address> acquires MyVouches{

      if (!exists<MyVouches>(val)) return vector::empty<address>();
      let state = borrow_global<MyVouches>(val);
      *&state.my_buddies
    }

    #[view]
    /// gets the buddies and checks if they are expired
    public fun all_not_expired(addr: address): vector<address> acquires MyVouches{
      let valid_vouches = vector::empty<address>();
      if (is_init(addr)) {
        let state = borrow_global<MyVouches>(addr);
        vector::for_each(state.my_buddies, |buddy_acc| {
          // account might have dropped
          if (account::exists_at(buddy_acc)){
            if (is_not_expired(buddy_acc, state)) {
              vector::push_back(&mut valid_vouches, buddy_acc)
            }
          }

        })
      };
      valid_vouches
    }

    #[view]
    /// filter expired vouches, and do ancestry check
    public fun true_friends(addr: address): vector<address> acquires MyVouches{

      if (!exists<MyVouches>(addr)) return vector::empty<address>();
      let not_expired = all_not_expired(addr);
      let filtered_ancestry = ancestry::list_unrelated(not_expired);
      filtered_ancestry
    }

    #[view]
    /// check if the user is in fact a valid voucher
    public fun is_valid_voucher_for(voucher: address, recipient: address):bool
    acquires MyVouches {
      let list = true_friends(recipient);
      vector::contains(&list, &voucher)
    }


    fun is_not_expired(voucher: address, state: &MyVouches): bool {
      let (found, i) = vector::index_of(&state.my_buddies, &voucher);
      if (found) {
        let when_vouched = vector::borrow(&state.epoch_vouched, i);
        return  (*when_vouched + EXPIRATION_ELAPSED_EPOCHS) > epoch_helper::get_current_epoch()
      };
      false
    }

    /// for a given list find and count any of my vouchers
    public(friend) fun true_friends_in_list(addr: address, list: &vector<address>): (vector<address>, u64) acquires MyVouches {

      if (!exists<MyVouches>(addr)) return (vector::empty(), 0);

      let tf = true_friends(addr);

      let buddies_in_list = vector::empty();
      let  i = 0;
      while (i < vector::length(&tf)) {
        let addr = vector::borrow(&tf, i);

        if (vector::contains(list, addr)) {
          vector::push_back(&mut buddies_in_list, *addr);
        };
        i = i + 1;
      };

      (buddies_in_list, vector::length(&buddies_in_list))
    }


    // TODO: move to globals
    // the cost to verify a vouch. Coins are burned.
    fun vouch_cost_microlibra(): u64 {
      1000
    }

    #[test_only]
    public fun test_set_buddies(val: address, buddy_list: vector<address>) acquires MyVouches {
      bulk_set(val, buddy_list);
    }
  }
