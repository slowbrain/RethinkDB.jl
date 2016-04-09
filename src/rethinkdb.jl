module RethinkDB

import JSON

type RethinkDBConnection
  socket :: Base.TCPSocket
end

# TODO: handle error is not connected or incorrect handshake
function connect(server::AbstractString = "localhost", port::Int = 28015)
  c = RethinkDBConnection(Base.connect(server, port))
  handshake(c)
  c
end

function handshake(conn::RethinkDBConnection)
  # Version.V0_4
  version = UInt32(0x400c2d20)

  # Key Size
  key_size = UInt32(0)

  # Protocol.JSON
  protocol = UInt32(0x7e6970c7)

  handshake = pack_command([version, key_size, protocol])
  write(conn.socket, handshake)
  is_valid_handshake(conn)
end

function is_valid_handshake(conn::RethinkDBConnection)
  readstring(conn.socket) == "SUCCESS"
end

function readstring(sock::TCPSocket, msg = "")
  c = read(sock, UInt8)
  s = convert(Char, c)
  msg = string(msg, s)
  if (s == '\0')
    return chop(msg)
  else
    readstring(sock, msg)
  end
end

function pack_command(args...)
  o = Base.IOBuffer()
  for enc_val in args
    write(o, enc_val)
  end
  o.data
end

function disconnect(conn::RethinkDBConnection)
  close(conn.socket)
end

# Have to do the funky push! on arrays due to
# the deprecated [] auto-concatenation still
# enabled in Julia 0.4

macro operate_on_zero_args(op_code::Int, name::Symbol)
  quote
    function $(esc(name))()
      retval = []
      push!(retval, $(op_code))
      retval
    end

    function $(esc(name))(query)
      retval = []
      push!(retval, $(op_code))

      sub = []
      push!(sub, query)

      push!(retval, sub)

      retval
    end
  end
end

macro operate_on_single_arg(op_code::Int, name::Symbol)
  quote
    function $(esc(name))(n)
      retval = []
      push!(retval, $(op_code))

      sub = []
      push!(sub, n)

      push!(retval, sub)

      retval
    end

    function $(esc(name))(query, n)
      retval = []
      push!(retval, $(op_code))

      sub = []
      push!(sub, query)
      push!(sub, n)

      push!(retval, sub)

      retval
    end
  end
end

# 10, var
# 11, javascript
@operate_on_single_arg(11, js)
@operate_on_single_arg(12, error)
# 13, implicit_var
@operate_on_single_arg(14, db)
@operate_on_single_arg(15, table)
# 16, get
# 17, eq
# 18, ne
# 19, lt
# 20, le
# 21, gt
# 22, ge
@operate_on_single_arg(23, not)
# 24, add
# 25, sub
# 26, mul
# 27, div
# 28, mod
# 29, append
# 30, slice
# 31, get_field
# 32, has_fields
# 33, pluck
# 34, without
# 35, merge
# 36, na
# 37, reduce
# 38, map
# 39, filter
# 40, concat_map
# 41, order_by
@operate_on_single_arg(42, distinct)
# 43, count
# 44, union
# 45, nth
# 46, na
# 47, na
# 48, inner_join
# 49, outer_join
# 50, eq_join
# 51, coerce_to
@operate_on_single_arg(52, type_of)
# 53, update
# 54, delete
# 55, replace
# 56, insert
@operate_on_single_arg(57, db_create)
@operate_on_single_arg(58, db_drop)
@operate_on_zero_args(59, db_list)
@operate_on_single_arg(60, table_create)
@operate_on_single_arg(61, table_drop)
@operate_on_single_arg(79, info)
@operate_on_single_arg(98, json)
@operate_on_single_arg(141, upcase)
@operate_on_single_arg(142, downcase)
# 149, split
@operate_on_single_arg(150, ungroup)
# 151, random
@operate_on_single_arg(153, http)
@operate_on_single_arg(154, args)
@operate_on_single_arg(157, geojson)
@operate_on_single_arg(158, to_geojson)
@operate_on_single_arg(167, fill)
@operate_on_single_arg(172, to_json)
@operate_on_single_arg(183, floor)
@operate_on_single_arg(184, ceil)
@operate_on_single_arg(185, round)

function exec(conn::RethinkDBConnection, q)
  j = JSON.json([1 ; Array[q]])
  send_command(conn, j)
end

function token()
  t = Array{UInt64}(1)
  t[1] = object_id(t)
  return t[1]
end

function send_command(conn::RethinkDBConnection, json)
  t = token()
  q = pack_command([ t, convert(UInt32, length(json)), json ])

  write(conn.socket, q)
  read_response(conn, t)
end

function read_response(conn::RethinkDBConnection, token)
  remote_token = read(conn.socket, UInt64)
  if remote_token != token
    return "Error"
  end

  len = read(conn.socket, UInt32)
  res = read(conn.socket, len)

  output = convert(UTF8String, res)
  JSON.parse(output)
end

function do_test()
  c = RethinkDB.connect()

  #db_create("tester") |> d -> exec(c, d) |> println
  #db_drop("tester") |> d -> exec(c, d) |> println
  #db_list() |> d -> exec(c, d) |> println

  db_create("test_db") |> d -> exec(c, d) |> println
  db("test_db") |> d -> table_create(d, "test_table") |> d -> exec(c, d) |> println
  #db("test_table") |> d -> table_drop("foo") |> d -> exec(c, d) |> println

  RethinkDB.disconnect(c)
end

end
