module bank {
  /// A state variable to store the balance of each account
  var balances: str -> int

  pure val ADDRESSES = Set("alice", "bob", "charlie")

  /// Increment balance of account by amount
  action deposit(account, amount) = {
    balances' = balances.setBy(account, curr => curr + amount)
  }

  /// Decrement balance of account by amount
  action withdraw(account, amount) = {
    balances' = balances.setBy(account, curr => curr - amount)
  }

  /// At the initial state, all balances are zero
  action init = {
    balances' = ADDRESSES.mapBy(_ => 0)
  }

  action step = {
    nondet account = ADDRESSES.oneOf()
    nondet amount = 1.to(100).oneOf()
    any {
      deposit(account, amount),
      withdraw(account, amount),
    }
  }

  /// An invariant stating that all accounts should have a non-negative balance
  val no_negatives = ADDRESSES.forall(addr => balances.get(addr) >= 0)
}
