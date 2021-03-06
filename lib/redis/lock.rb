require 'redis'

class Redis
  module Lock
    
    # Lock a given key for updating
    #
    # Example:
    #
    # $redis = Redis.new
    # lock_for_update('beers_on_the_wall', 20, 1000) do
    #   $redis.decr('beers_on_the_wall')
    # end
    
    def lock_for_update(key, timeout = 60, max_attempts = 100)
      if self.lock(key, timeout, max_attempts)
        response = yield if block_given?
        self.unlock(key)
        return response
      end
    end
    
    # Lock a given key.  Optionally takes a timeout and max number of attempts to lock the key before giving up.
    # 
    # Example:
    # 
    # $redis.lock('beers_on_the_wall', 10, 100)
    
    def lock(key, timeout = 60, max_attempts = 100)
      current_lock_key = lock_key(key)
      expiration_value = lock_expiration(timeout)
      attempt_counter = 0
      begin
        if self.setnx(current_lock_key, expiration_value)
          return true
        else
          current_lock = self.get(current_lock_key)
          if (current_lock.to_s.split('-').first.to_i) < Time.now.to_i
            compare_value = self.getset(current_lock_key, expiration_value)
            return true if compare_value == current_lock
          end
        end
      
        raise "Unable to acquire lock for #{key}."
      rescue => e
        if e.message == "Unable to acquire lock for #{key}."
          if attempt_counter == max_attempts
            raise
          else
            attempt_counter += 1
            sleep 1
            retry
          end
        else
          raise
        end
      end
    end
    
    # Unlock a previously locked key if it has not expired and the current process was the one that locked it.
    # 
    # Example:
    # 
    # $redis.unlock('beers_on_the_wall')
    
    def unlock(key)
      current_lock_key = lock_key(key)
      lock_value = self.get(current_lock_key)
      return true unless lock_value
      lock_timeout, lock_holder = lock_value.split('-')
      if (lock_timeout.to_i > Time.now.to_i) && (lock_holder.to_i == Process.pid)
        self.del(current_lock_key)
        return true
      else
        return false
      end
    end
  
    private
  
    def lock_expiration(timeout)
      "#{Time.now.to_i + timeout + 1}-#{Process.pid}"
    end
  
    def lock_key(key)
      "lock:#{key}"
    end
  
  end
end