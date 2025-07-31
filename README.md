# Minidote - A Causally Consistent CRDT Database

A distributed, causally-consistent CRDT (Conflict-free Replicated Data Type) database implementation in Elixir. This project implements the requirements specified in ex-final.pdf for the Programming Distributed Systems course.

## Features

### Core Implementation (Section 1)
- **Causally Consistent CRDT Database**: Full implementation with eventual visibility, causality, correct return values, atomic operations, and session guarantees
- **Six CRDT Types**: 
  - `:counter_pn_ob`: Increment/decrement counter (operation-based)
  - `:counter_pn_sb`: Increment/decrement counter (state-based)
  - `:set_aw_op`: Add-wins set with add/remove operations (operation-based)
  - `:set_rw_op`: Remove-wins set with add/remove operations (operation-based)
  - `:mv_register`: Multi-value register supporting concurrent assignments (operation-based)
  - `:lww_register`: Last-writer-wins register with timestamp-based conflict resolution (operation-based)
- **Vector Clock-based Causality**: Ensures causal ordering of updates across replicas
- **Session Guarantees**: Read-your-writes and monotonic read consistency
- **Atomic Operations**: Multi-object updates are applied atomically

### Additional Feature (Section 2.1)
- **Crash Recovery and Log Pruning**: Persistent storage using DETS with automatic log pruning to prevent unbounded growth
- **Automatic State Snapshots**: Periodic snapshots of CRDT states for efficient recovery
- **Operation Logging**: All updates are logged for crash recovery

## Architecture

```
Client 1    Client 2    Client ...
    |           |            |
    +-------- Minidote API --------+
                    |
             MinidoteServer
                    |
            CausalBroadcast ---- other nodes
                    |
              PersistenceManager
                    |
            [DETS Storage Files]
```

### Key Components

- **Minidote**: Main API module providing `read_objects/2` and `update_objects/2`
- **Minidote.Server**: GenServer managing CRDT states and handling causally consistent operations
- **CausalBroadcast**: Vector clock-based causal broadcast for distributed updates
- **PersistenceManager**: Handles crash recovery and log pruning using DETS storage
- **CRDT Behaviours**: Individual CRDT implementations following the behaviour pattern

## Usage

### Basic Operations

```elixir
# Define keys (3-tuple: {identifier, CRDT_type, bucket})
counter_key = {"my_counter", :counter_pn_ob, "counters"}
set_key = {"my_set", :set_aw_op, "sets"}
register_key = {"my_register", :mv_register, "registers"}

# Update operations
{:ok, clock1} = Minidote.update_objects([
  {counter_key, :increment, 5},
  {set_key, :add, "item1"}
], :ignore)

# Read operations
{:ok, results, clock2} = Minidote.read_objects([counter_key, set_key], clock1)

# Session guarantees - use returned clock for consistency
{:ok, clock3} = Minidote.update_objects([{counter_key, :decrement, 2}], clock2)
```

### CRDT Operations

#### :counter_pn_ob & :counter_pn_sb
- `:increment` or `{:increment, amount}`
- `:decrement` or `{:decrement, amount}`

#### :set_aw_op & :set_rw_op  
- `{:add, element}`
- `{:add_all, [elements]}`
- `{:remove, element}`
- `{:remove_all, [elements]}`
- `{:reset}`

#### :mv_register
- `{:assign, value}`
- `{:reset}`

#### :lww_register
- `{:assign, value}`
- `{:reset}`

## Running the System

### Single Node
```bash
mix deps.get
mix compile
iex -S mix
```

### Distributed Cluster
```bash
# Terminal 1
iex --name minidote1@127.0.0.1 -S mix

# Terminal 2  
iex --name minidote2@127.0.0.1 -S mix

# Terminal 3
iex --name minidote3@127.0.0.1 -S mix
```

### Testing
```bash
mix test
```

### Example Usage
```bash
mix run example_usage.exs
```

## Data Model

Keys are 3-tuples: `{Key, Type, Bucket}` where:
- **Key**: Binary identifier for the object
- **Type**: CRDT type atom (:counter_pn_ob, :set_aw_op, :mv_register, etc.)  
- **Bucket**: Binary namespace for grouping objects

Clocks are vector clocks represented as maps: `%{node_name => timestamp}`

## Consistency Guarantees

1. **Eventual Visibility**: All updates eventually become visible at all replicas
2. **Causality**: If e1 →vis e2 and e2 →vis e3, then e1 →vis e3
3. **Correct Return Values**: Each CRDT follows its specification
4. **Atomic Operations**: Multi-object updates are atomic
5. **Session Guarantees**: Read-your-writes and monotonic reads

## Files and Persistence

- `minidote_state_<node>.dets`: Current CRDT states snapshot
- `minidote_log_<node>.dets`: Operation log for crash recovery
- Automatic log pruning keeps last 1000 operations
- Snapshots taken every 10 seconds

## Acknowledgements

**AI Tool Usage**: This project was implemented with assistance from Claude (Anthropic's AI assistant) for code generation, debugging, and architectural guidance. All code was reviewed, understood, and validated by the author.

Implementation follows the architecture described in the course materials and references:
- Marc Shapiro, Nuno Preguiça, Carlos Baquero, Marek Zawirski (2011): "A comprehensive study of Convergent and Commutative Replicated Data Types"
- AntidoteDB CRDT library for reference patterns

## Development Notes

This is a straightforward implementation suitable for educational purposes and small-scale distributed systems. The design prioritizes simplicity and correctness over performance optimization.
