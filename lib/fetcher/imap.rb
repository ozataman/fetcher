require File.dirname(__FILE__) + '/../vendor/plain_imap'

module Fetcher
  class Imap < Base
    
    PORT = 143
    
    protected
    
    # Additional Options:
    # * <tt>:authentication</tt> - authentication type to use, defaults to PLAIN
    # * <tt>:port</tt> - port to use (defaults to 143)
    # * <tt>:ssl</tt> - use SSL to connect
    # * <tt>:use_login</tt> - use LOGIN instead of AUTHENTICATE to connect (some IMAP servers, like GMail, do not support AUTHENTICATE)
    # * <tt>:processed_folder</tt> - if set to the name of a mailbox, messages will be moved to that mailbox instead of deleted after processing. The mailbox will be created if it does not exist.
    # * <tt>:error_folder:</tt> - the name of a mailbox where messages that cannot be processed (i.e., your receiver throws an exception) will be moved. Defaults to "bogus". The mailbox will be created if it does not exist.
    # * <tt>:retries:</tt> - number of times to retry download before a message is marked erroneous
    def initialize(options={})
      @authentication = options.delete(:authentication) || 'PLAIN'
      @port = options.delete(:port) || PORT
      @ssl = options.delete(:ssl)
      @use_login = options.delete(:use_login)
      @processed_folder = options.delete(:processed_folder)
      @error_folder = options.delete(:error_folder) || 'bogus'
      @retries = options.delete(:retries) || 1
      super(options)
    end
    
    # Open connection and login to server
    def establish_connection
      @connection = Net::IMAP.new(@server, @port, @ssl)
      if @use_login
        @connection.login(@username, @password)
      else
        @connection.authenticate(@authentication, @username, @password)
      end
    end
    
    # Retrieve messages from server
    def get_messages
      @connection.select('INBOX')
      @connection.uid_search(['ALL']).each do |uid|
        msg = @connection.uid_fetch(uid,'RFC822').first.attr['RFC822']
        passes = 0
        begin
          process_message(msg)
          add_to_processed_folder(uid) if @processed_folder
        rescue
          if (passes += 1) >= @retries
            handle_bogus_message(msg)
          else
            retry
          end
        end
        # Mark message as deleted 
        @connection.uid_store(uid, "+FLAGS", [:Seen, :Deleted])
      end
    end
    
    # Notify the receiver and store the message for inspection if the receiver errors
    def handle_bogus_message(message)
      notify_receiver_with_exception(message)
      create_mailbox(@error_folder)
      @connection.append(@error_folder, message)
    end
    
    # Delete messages and log out
    def close_connection
      @connection.expunge
      @connection.logout
      @connection.disconnect
    rescue => ex
      # Rails.logger.error(ex)
    end
    
    def add_to_processed_folder(uid)
      create_mailbox(@processed_folder)
      @connection.uid_copy(uid, @processed_folder)
    end
    
    def create_mailbox(mailbox)
      unless @connection.list("", mailbox)
        @connection.create(mailbox)
      end
    end
    
  end
end
