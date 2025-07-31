#!/usr/bin/env elixir

# Example usage of the Minidote CRDT database
# This demonstrates the basic functionality including different CRDT types,
# session guarantees, and crash recovery.

IO.puts("=== Minidote CRDT Database Example ===")

# Define some keys for different CRDT types
counter_key = {"my_counter", :counter_pn_ob, "counters"}
set_key = {"my_set", :set_aw_op, "collections"}  
register_key = {"my_register", :mv_register, "registers"}

IO.puts("\n1. Counter Operations:")
IO.puts("Initial increment by 10...")
{:ok, clock1} = Minidote.update_objects([{counter_key, :increment, 10}], :ignore)
IO.puts("Clock after increment: #{inspect clock1}")

{:ok, results1, clock2} = Minidote.read_objects([counter_key], clock1)
[{_key, value1}] = results1
IO.puts("Counter value: #{value1}")

IO.puts("Decrement by 3...")
{:ok, clock3} = Minidote.update_objects([{counter_key, :decrement, 3}], clock2)

{:ok, results2, _clock4} = Minidote.read_objects([counter_key], clock3)
[{_key, value2}] = results2
IO.puts("Counter value after decrement: #{value2}")

IO.puts("\n2. Set Operations:")
IO.puts("Adding elements to set...")
{:ok, clock5} = Minidote.update_objects([
  {set_key, :add, "apple"},
  {set_key, :add, "banana"},
  {set_key, :add, "cherry"}
], clock3)

{:ok, results3, clock6} = Minidote.read_objects([set_key], clock5)
[{_key, set_value}] = results3
IO.puts("Set contents: #{inspect set_value}")

IO.puts("Removing 'banana'...")
{:ok, clock7} = Minidote.update_objects([{set_key, :remove, "banana"}], clock6)

{:ok, results4, _clock8} = Minidote.read_objects([set_key], clock7)
[{_key, set_value2}] = results4
IO.puts("Set contents after removal: #{inspect set_value2}")

IO.puts("\n3. Multi-Value Register Operations:")
IO.puts("Assigning value 'hello'...")
{:ok, clock9} = Minidote.update_objects([{register_key, :assign, "hello"}], clock7)

{:ok, results5, clock10} = Minidote.read_objects([register_key], clock9)
[{_key, register_value}] = results5
IO.puts("Register value: #{inspect register_value}")

IO.puts("Assigning value 'world'...")
{:ok, clock11} = Minidote.update_objects([{register_key, :assign, "world"}], clock10)

{:ok, results6, _clock12} = Minidote.read_objects([register_key], clock11)
[{_key, register_value2}] = results6
IO.puts("Register value after reassignment: #{inspect register_value2}")

IO.puts("\n4. Atomic Operations:")
IO.puts("Updating multiple objects atomically...")
{:ok, final_clock} = Minidote.update_objects([
  {counter_key, :increment, 5},
  {set_key, :add, "date"},
  {register_key, :assign, "atomic_update"}
], clock11)

{:ok, final_results, _} = Minidote.read_objects([counter_key, set_key, register_key], final_clock)

IO.puts("Final state after atomic update:")
Enum.each(final_results, fn {{key_id, type, _bucket}, value} ->
  IO.puts("  #{key_id} (#{type}): #{inspect value}")
end)

IO.puts("\n=== Example completed successfully! ===")
IO.puts("The database now contains persistent state that will survive crashes.")
IO.puts("Vector clock: #{inspect final_clock}")