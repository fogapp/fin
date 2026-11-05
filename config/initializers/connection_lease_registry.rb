# Before Ruby 3.3.5, ActiveRecord tracks which thread holds which connection
# in its own WeakThreadKeyMap: a plain Hash it leaves unsynchronized, trusting
# the GVL. But its writer prunes dead threads with `select!`, and the GVL can
# switch threads mid-iteration — so a second thread taking its first
# connection right then (Solid Queue's scheduler enqueuing a recurring task)
# raises "can't add a new key into hash during iteration". Serialize the
# writes. Ruby 3.3.5+ uses ObjectSpace::WeakKeyMap instead and skips this.
#
# One lock shared by every map, not one per instance: a pool built before
# this file loads already holds its map, and the writes are rare and tiny.
map = ActiveRecord::ConnectionAdapters::ConnectionPool::WeakThreadKeyMap
unless defined?(ObjectSpace::WeakKeyMap) && map == ObjectSpace::WeakKeyMap
  write_lock = Mutex.new

  map.prepend(Module.new do
    define_method(:[]=) { |key, value| write_lock.synchronize { super(key, value) } }
    define_method(:clear) { write_lock.synchronize { super() } }
  end)
end
