local migration = require("unified_review.persist.migration")

describe("session persistence migration", function()
	it("defaults missing versions to the current version", function()
		local migrated, err = migration.migrate({ threads = {} })

		assert.is_nil(err)
		assert.are.equal(migration.current_version, assert(migrated).version)
	end)

	it("passes current-version data through", function()
		local data = { version = migration.current_version, threads = { { id = "thread-1" } } }
		local migrated, err = migration.migrate(data)

		assert.is_nil(err)
		assert.are.same(data, migrated)
	end)

	it("rejects newer unsupported versions", function()
		local migrated, err = migration.migrate({ version = migration.current_version + 1 })

		assert.is_nil(migrated)
		assert.is_not_nil(err)
		assert.matches("unsupported session store version", assert(err).message)
	end)

	it("handles nil persisted data as an empty current store", function()
		local migrated, err = migration.migrate(nil)

		assert.is_nil(err)
		assert.are.equal(migration.current_version, assert(migrated).version)
	end)
end)
