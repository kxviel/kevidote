# Minidote - Simple CRDT Database

A distributed CRDT (Conflict-free Replicated Data Type) database in Elixir for the Programming Distributed Systems course.

## Features

- **6 CRDT Types**: Counters, Sets (add-wins/remove-wins), Registers (multi-value/last-writer-wins)
- **Causal Consistency**: Vector clocks ensure proper ordering
- **Session Guarantees**: Read-your-writes consistency
- **Crash Recovery**: Persistent logging with automatic snapshots

## Usage

```elixir
# Update operations
key = {"my_counter", :counter_pn_ob, "bucket"}
{:ok, clock} = Minidote.update_objects([{key, :increment, 5}], :ignore)

# Read operations  
{:ok, results, new_clock} = Minidote.read_objects([key], clock)
```

### CRDT Operations
- **Counters**: `:increment`, `:decrement` (with optional amounts)
- **Sets**: `{:add, item}`, `{:remove, item}`
- **Registers**: `{:assign, value}`

## Setup

```bash
mix deps.get
mix test
iex -S mix
```

## Testing

```bash
mix test                    # Run all tests
mix test test/basic_*       # Run basic functionality tests 
mix test test/crash_*       # Run crash recovery tests
```

## Key Structure

Keys are 3-tuples: `{identifier, crdt_type, bucket}`

## Acknowledgements

Built with assistance from Claude AI for the Programming Distributed Systems course.
