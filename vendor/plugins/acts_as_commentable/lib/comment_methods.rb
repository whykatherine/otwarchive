module CommentMethods
  
  def self.included(comment)
    comment.class_eval do      
      extend ClassMethods
      include InstanceMethods
    end
  end 
  
  module ClassMethods
    # Returns the last thread number assigned
    def max_thread
      Comment.maximum(:thread)
    end
  end

  module InstanceMethods
    
    # Sets pseud, depth and thread values and adjusts threading for sub-comments
    def set_and_save
      self.set_depth
      if self.reply_comment?
        old_comment = Comment.find(self.commentable_id)
        self.thread = old_comment.thread
        old_comment.add_child(self)

        # Disabling email for now but leaving this here as a placeholder
        # if old_comment.pseud_id
        #   recipient = User.find(old_comment.pseud.user_id)
        #   UserMailer.deliver_send_comments(recipient, self)
        # end

      else
        if Comment.max_thread
          self.thread = Comment.max_thread.to_i + 1
        else
          self.thread = 1
        end
        self.save
      end
    end
    
    # Only destroys childless comments, sets is_deleted to true for the rest
    def destroy_or_mark_deleted
      if self.children_count > 0 
        self.is_deleted = true
        self.save
      else
        self.destroy
      end  
    end
    
    # Returns true if the comment is a reply to another comment                     
    def reply_comment?
      self.commentable_type == self.class.to_s
    end

    # Sets the depth value for threaded display purposes (higher depth value = more indenting)                     
    def set_depth
      if self.reply_comment?
        self.depth = self.commentable.depth + 1 
      else
        self.depth = 0
      end
    end     

    # Returns the total number of sub-comments
    def children_count
      if self.threaded_right
        return (self.threaded_right - self.threaded_left - 1)/2
      else
        return 0
      end
    end

    # Returns all sub-comments plus the comment itself 
    # Returns comment itself if unthreaded
    def full_set 
      if self.threaded_left
        Comment.find(:all, :conditions => ["threaded_left BETWEEN (?) and (?) AND thread = (?)", self.threaded_left, self.threaded_right, self.thread],
                            :include => :pseud)
      else
        return [self]
      end
    end

    # Returns all sub-comments
    def all_children
      if self.children_count > 0
        Comment.find(:all, :conditions => ["threaded_left > (?) and threaded_right < (?) and thread = (?)", self.threaded_left, self.threaded_right, self.thread],
                            :include => :pseud)
      end
    end

    # Returns a full comment thread
    def full_thread
      Comment.find(:all, :conditions => ["thread = (?)", self.thread])
    end
            

    # Adds a child to this object in the tree. This method will update all of the
    # other elements in the tree and shift them to the right, keeping everything
    # balanced. 
    def add_child( child )
      #self.reload
      #child.reload

      if ( (self.threaded_left == nil) || (self.threaded_right == nil) )
        # Looks like we're now the root node!  Woo
        self.threaded_left = 1
        self.threaded_right = 4

        # What do to do about validation?
        return nil unless self.save

        child.commentable_id = self.id
        child.threaded_left = 2
        child.threaded_right= 3
        return child.save
      else
        # OK, we need to add and shift everything else to the right
        child.commentable_id = self.id
        right_bound = self.threaded_right
        child.threaded_left = right_bound
        child.threaded_right = right_bound + 1
        self.threaded_right += 2
        # Updates all comments in the thread to set their relative positions
        Comment.transaction {
          Comment.update_all("threaded_left = (threaded_left + 2)", ["thread = (?) AND threaded_left >= (?)", self.thread, right_bound])
          Comment.update_all("threaded_right = (threaded_right + 2)",  ["thread = (?) AND threaded_right >= (?)", self.thread, right_bound])
          self.save
          child.save
        }
      end
    end  
  end
end