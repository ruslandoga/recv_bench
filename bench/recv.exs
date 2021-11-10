# Rexbug.start(["SyncAcceptor :: return", "AcceptorPool :: return"], msgs: 100, time: 100)

{:ok, _pid} =
  AcceptorPool.start_link(
    acceptor: PassiveAcceptor,
    port: 8091,
    accept_timeout: 20_000,
    receive_timeout: 20_000,
    socket_opts: [
      reuseaddr: true,
      backlog: 32768,
      packet: :raw,
      active: false
    ]
  )

{:ok, _pid} =
  AcceptorPool.start_link(
    acceptor: ActiveAcceptor,
    port: 8092,
    accept_timeout: 20_000,
    receive_timeout: 20_000,
    socket_opts: [
      reuseaddr: true,
      backlog: 32768,
      packet: :raw,
      active: true
    ]
  )

{:ok, _pid} =
  AcceptorPool.start_link(
    acceptor: ActiveOnceAcceptor,
    port: 8093,
    accept_timeout: 20_000,
    receive_timeout: 20_000,
    socket_opts: [
      reuseaddr: true,
      backlog: 32768,
      packet: :raw,
      active: :once
    ]
  )

# {:ok, _pid} = GenServer.start_link(AcceptorPool, acceptor: ActiveNAcceptor, port: 5003)

# ~8.5KB per connection
sockets1 =
  Enum.map(1..10000, fn _ ->
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, 8091, [:binary, active: true])
    socket
  end)

socket1 = hd(sockets1)

sockets2 =
  Enum.map(1..20, fn _ ->
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, 8092, [:binary, active: true])
    socket
  end)

socket2 = hd(sockets2)

sockets3 =
  Enum.map(1..20, fn _ ->
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, 8093, [:binary, active: true])
    socket
  end)

socket3 = hd(sockets3)

# TODO compare with ranch and bandit
# TODO load all 20 socket in parallel
# TODO tune tcp stack, :gen_tcp options
# TODO try on aws

# packet = String.duplicate("a", 1000)

packet = """
{
  "firstName": "John",
  "lastName": "Smith",
  "isAlive": true,
  "age": 27,
  "address": {
    "streetAddress": "21 2nd Street",
    "city": "New York",
    "state": "NY",
    "postalCode": "10021-3100"
  },
  "phoneNumbers": [
    {
      "type": "home",
      "number": "212 555-1234"
    },
    {
      "type": "office",
      "number": "646 555-4567"
    }
  ],
  "children": [],
  "spouse": null
}
"""

Benchee.run(%{
  "sync acceptor" => fn -> :gen_tcp.send(socket1, packet) end,
  "async acceptor" => fn -> :gen_tcp.send(socket2, packet) end,
  "async once acceptor" => fn -> :gen_tcp.send(socket3, packet) end
})
