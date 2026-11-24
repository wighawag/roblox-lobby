--!strict
-- A minimal signal: connect, once, fire, disconnect. Pure Luau (no Roblox API), so it runs in Lune too.
-- Handlers run synchronously, in connection order; an error in one handler is reported and does not stop the others.

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }
export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}

function Signal.new(onError: ((err: any) -> ())?): Signal
	local handlers: { { fn: (...any) -> (), conn: Connection } } = {}
	local report = onError or function(err)
		warn("[RobloxLobby] signal handler error: " .. tostring(err))
	end

	local self = {}

	function self.Connect(_: any, handler: (...any) -> ()): Connection
		local conn = { Connected = true } :: any
		function conn.Disconnect(c: any)
			if not c.Connected then
				return
			end
			c.Connected = false
			for i, h in handlers do
				if h.conn == c then
					table.remove(handlers, i)
					break
				end
			end
		end
		table.insert(handlers, { fn = handler, conn = conn })
		return conn
	end

	function self.Once(s: any, handler: (...any) -> ()): Connection
		local conn: Connection
		conn = s:Connect(function(...)
			conn:Disconnect()
			handler(...)
		end)
		return conn
	end

	function self.Fire(_: any, ...: any)
		-- copy, so handlers may connect or disconnect while firing
		local snapshot = table.clone(handlers)
		for _, h in snapshot do
			if h.conn.Connected then
				local ok, err = pcall(h.fn, ...)
				if not ok then
					report(err)
				end
			end
		end
	end

	function self.DisconnectAll(_: any)
		for _, h in handlers do
			h.conn.Connected = false
		end
		table.clear(handlers)
	end

	return (self :: any) :: Signal
end

return Signal
