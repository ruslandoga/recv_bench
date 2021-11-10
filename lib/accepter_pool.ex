defmodule TCP do
  def accept(pool, listen_socket, accept_timeout) do
    with {:ok, _socket} = success <- :gen_tcp.accept(listen_socket, accept_timeout) do
      GenServer.cast(pool, :accepted)
      success
    end
  end
end

defmodule PassiveAcceptor do
  @moduledoc false
  require Logger

  def start_link(pool, listen_socket, opts) do
    :proc_lib.spawn_link(__MODULE__, :accept, [pool, listen_socket, opts])
  end

  @doc false
  def accept(pool, listen_socket, opts) do
    case TCP.accept(pool, listen_socket, opts.accept_timeout) do
      {:ok, socket} -> __MODULE__.recv_loop(socket, opts)
      {:error, :timeout} -> __MODULE__.accept(pool, listen_socket, opts)
      {:error, :econnaborted} -> __MODULE__.accept(pool, listen_socket, opts)
      {:error, :closed} -> :ok
      {:error, other} -> exit({:error, other})
    end
  end

  @doc false
  def recv_loop(socket, opts) do
    case :gen_tcp.recv(socket, 0, opts.receive_timeout) do
      {:ok, _data} ->
        # Logger.debug("#{inspect(self())}: recv #{byte_size(data)}")
        __MODULE__.recv_loop(socket, opts)

      {:error, :timeout} ->
        :gen_tcp.close(socket)
        exit(:normal)

      {:error, closed} when closed == :closed or closed == :enotconn ->
        :gen_tcp.close(socket)
        exit(:normal)
    end
  end
end

defmodule ActiveAcceptor do
  @moduledoc false
  require Logger

  def start_link(pool, listen_socket, opts) do
    :proc_lib.spawn_link(__MODULE__, :accept, [pool, listen_socket, opts])
  end

  @doc false
  def accept(pool, listen_socket, opts) do
    case TCP.accept(pool, listen_socket, opts.accept_timeout) do
      {:ok, socket} -> __MODULE__.recv_loop(socket, opts)
      {:error, :timeout} -> __MODULE__.accept(pool, listen_socket, opts)
      {:error, :econnaborted} -> __MODULE__.accept(pool, listen_socket, opts)
      {:error, :closed} -> :ok
      {:error, other} -> exit({:error, other})
    end
  end

  @doc false
  def recv_loop(socket, opts) do
    receive do
      {:tcp, _port, _data} ->
        # Logger.debug("#{inspect(self())}: recv #{byte_size(data)}")
        recv_loop(socket, opts)

      {:tcp_closed, _socket} ->
        :ok
    end
  end
end

defmodule ActiveOnceAcceptor do
  @moduledoc false
  require Logger

  def start_link(pool, listen_socket, opts) do
    :proc_lib.spawn_link(__MODULE__, :accept, [pool, listen_socket, opts])
  end

  @doc false
  def accept(pool, listen_socket, opts) do
    case TCP.accept(pool, listen_socket, opts.accept_timeout) do
      {:ok, socket} -> __MODULE__.recv_loop(socket, opts)
      {:error, :timeout} -> __MODULE__.accept(pool, listen_socket, opts)
      {:error, :econnaborted} -> __MODULE__.accept(pool, listen_socket, opts)
      {:error, :closed} -> :ok
      {:error, other} -> exit({:error, other})
    end
  end

  @doc false
  def recv_loop(socket, opts) do
    receive do
      {:tcp, _port, _data} ->
        # Logger.debug("#{inspect(self())}: recv #{byte_size(data)}")
        :inet.setopts(socket, active: :once)
        recv_loop(socket, opts)

      {:tcp_closed, _socket} ->
        :ok
    end
  end
end

defmodule AcceptorPool do
  @moduledoc "ranch-like tcp acceptor pool"
  use GenServer
  require Logger

  def start_link(opts) do
    {socket_opts, opts} = Keyword.pop!(opts, :socket_opts)
    GenServer.start_link(__MODULE__, {opts, socket_opts}, name: opts[:name])
  end

  @impl true
  def init({opts, socket_opts}) do
    Process.flag(:trap_exit, true)

    %{acceptor: acceptor, port: port} = opts = Map.new(opts)

    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary] ++ socket_opts)

    min_acceptors = opts[:min_acceptors] || 20
    acceptors = :ets.new(:acceptors, [:private, :set])

    Enum.each(1..min_acceptors, fn _ ->
      pid = acceptor.start_link(self(), listen_socket, opts)
      :ets.insert(acceptors, {pid})
    end)

    {:ok, %{socket: listen_socket, acceptors: acceptors, opts: opts}}
  end

  def acceptors(pool) do
    GenServer.call(pool, :acceptors)
  end

  @impl true
  def handle_call(:acceptors, _from, state) do
    {:reply, :ets.tab2list(state.acceptors), state}
  end

  @impl true
  def handle_cast(:accepted, state) do
    {:noreply, start_add_acceptor(state)}
  end

  @impl true
  def handle_info({:EXIT, _pid, {:error, :emfile}}, state) do
    Logger.error("no more file descriptors, shutting down")
    {:stop, :emfile, state}
  end

  def handle_info({:EXIT, pid, :normal}, state) do
    {:noreply, remove_acceptor(state, pid)}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.error("acceptor #{inspect(pid)} exit: #{inspect(reason)}")
    {:noreply, remove_acceptor(state, pid)}
  end

  defp remove_acceptor(state, pid) do
    :ets.delete(state.acceptors, pid)
    state
  end

  defp start_add_acceptor(
         %{socket: listen_socket, acceptors: acceptors, opts: %{acceptor: acceptor} = opts} =
           state
       ) do
    pid = acceptor.start_link(self(), listen_socket, opts)
    :ets.insert(acceptors, {pid})
    state
  end
end
