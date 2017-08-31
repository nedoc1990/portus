module Portus
  # The DB module has useful methods for DB purposes.
  module DB
    # Pings the DB and returns a proper symbol depending on the situation:
    #   * ready: the database has been created and initialized.
    #   * empty: the database has been created but has not been initialized.
    #   * missing: the database has not been created.
    #   * down: cannot connect to the database.
    #   * unknown: there has been an unexpected error.
    def self.ping
      ::Portus::DB.migrations? ? :ready : :empty
    rescue ActiveRecord::NoDatabaseError
      :missing
    rescue Mysql2::Error
      :down
    rescue
      :unknown
    end

    # Returns true if the migrations have been run. The implementation is pretty
    # trivial, but this gives us a nice way to test this module.
    def self.migrations?
      ActiveRecord::Base.connection
      ActiveRecord::Base.connection.table_exists? "schema_migrations"
    end
  end
end
