import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import fs from "fs"
import os from "os"
import path from "path"

import { readTomlDefaultConnection, resetTomlConfigCache } from "../../lib/snowflake"

// ---------------------------------------------------------------------------
// Module-level mocks (hoisted)
// ---------------------------------------------------------------------------

// Automock fs and os for readTomlDefaultConnection tests (setupFiles helper below).
// The new querySnowflake / REST-helper tests use vi.resetModules() + vi.doMock()
// inside their own beforeEach so they get fresh module instances — these top-level
// mocks don't interfere with those tests.
vi.mock("fs")
vi.mock("os")

// smol-toml is loaded via require() inside the function; provide it via mock
vi.mock("smol-toml", () => {
  const { parse } = require("smol-toml") as { parse: (s: string) => Record<string, any> }
  return { parse }
})

vi.mock("next/headers", () => ({
  headers: vi.fn(() => ({ get: vi.fn(() => null) })),
}))

// createPool mock used by querySnowflake retry tests.
// mockExecuteImpl is set per-test inside the describe block below.
let mockExecuteImpl: (opts: {
  sqlText: string
  complete: (err: Error | null, stmt: Record<string, unknown> | null, rows: Record<string, unknown>[] | null) => void
}) => void

vi.mock("snowflake-sdk", () => ({
  default: {
    configure: vi.fn(),
    createPool: vi.fn(() => ({
      use: (fn: (conn: { execute: typeof mockExecuteImpl; destroy: (cb?: () => void) => void }) => Promise<unknown>) => {
        const conn = {
          execute: (opts: Parameters<typeof mockExecuteImpl>[0]) => mockExecuteImpl(opts),
          destroy: vi.fn((cb?: () => void) => cb?.()),
        }
        return fn(conn)
      },
      drain: vi.fn(),
    })),
  },
}))

// ---------------------------------------------------------------------------
// readTomlDefaultConnection helpers
// ---------------------------------------------------------------------------

const HOME = "/mock-home"

function setupFiles(files: Record<string, string>) {
  vi.mocked(os.homedir).mockReturnValue(HOME)
  vi.mocked(fs.existsSync).mockImplementation((p) => {
    return typeof p === "string" && p in files
  })
  vi.mocked(fs.readFileSync).mockImplementation((p, _enc) => {
    const content = files[String(p)]
    if (content === undefined) throw new Error(`ENOENT: ${p}`)
    return content
  })
}

const ENV_KEYS_TO_CLEAR = [
  "SNOWFLAKE_CONNECTION_NAME",
  "SNOWFLAKE_HOME",
  "SNOWFLAKE_ACCOUNT",
  "SNOWFLAKE_USER",
  "SNOWFLAKE_PASSWORD",
  "SNOWFLAKE_DATABASE",
  "SNOWFLAKE_SCHEMA",
  "SNOWFLAKE_ROLE",
  "SNOWFLAKE_WAREHOUSE",
]

// fs mock factory that blocks toml config reads (used by URL / auth header tests)
function makeNoTomlFsMock() {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const actual = require("fs") as typeof import("fs")
  const overrides = {
    existsSync: (p: string) => {
      if (p.endsWith("connections.toml") || p.endsWith("config.toml")) return false
      return actual.existsSync(p)
    },
    readFileSync: actual.readFileSync,
  }
  return { default: { ...actual, ...overrides }, ...overrides }
}

// ---------------------------------------------------------------------------
// readTomlDefaultConnection
// ---------------------------------------------------------------------------

describe("readTomlDefaultConnection", () => {
  beforeEach(() => {
    resetTomlConfigCache()
    for (const key of ENV_KEYS_TO_CLEAR) {
      delete process.env[key]
    }
  })

  afterEach(() => {
    vi.restoreAllMocks()
    delete process.env.SNOWFLAKE_RANDOM_KEY
  })

  it("returns null when neither file exists", () => {
    setupFiles({})
    expect(readTomlDefaultConnection()).toBeNull()
  })

  it("reads connections from connections.toml (legacy top-level format)", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        default_connection_name = "prod"
        [prod]
        account = "myaccount"
        user = "myuser"
        password = "mypass"
        warehouse = "mywh"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("myaccount")
    expect(conn!.user).toBe("myuser")
    expect(conn!.warehouse).toBe("mywh")
  })

  it("reads connections from config.toml legacy layout when connections.toml is absent", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "config.toml")]: `
        default_connection_name = "legacy"
        [connections.legacy]
        account = "legacy-acct"
        user = "legacy-user"
        password = "legacy-pass"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("legacy-acct")
    expect(conn!.user).toBe("legacy-user")
  })

  it("prefers connections.toml over config.toml when both exist", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [modern]
        account = "modern-acct"
        user = "modern-user"
        password = "modern-pass"
      `,
      [path.join(HOME, ".snowflake", "config.toml")]: `
        [connections.legacy]
        account = "legacy-acct"
        user = "legacy-user"
        password = "legacy-pass"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("modern-acct")
  })

  it("picks up default_connection_name from config.toml when connections.toml has none", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [alpha]
        account = "alpha-acct"
        user = "alpha-user"
        password = "alpha-pass"
        [beta]
        account = "beta-acct"
        user = "beta-user"
        password = "beta-pass"
      `,
      [path.join(HOME, ".snowflake", "config.toml")]: `
        default_connection_name = "beta"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("beta-acct")
  })

  it("SNOWFLAKE_CONNECTION_NAME env var overrides file defaults", () => {
    process.env.SNOWFLAKE_CONNECTION_NAME = "second"

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        default_connection_name = "first"
        [first]
        account = "first-acct"
        user = "first-user"
        password = "first-pass"
        [second]
        account = "second-acct"
        user = "second-user"
        password = "second-pass"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("second-acct")
  })

  it("falls back to first connection when default name does not match any", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        default_connection_name = "nonexistent"
        [myconn]
        account = "fallback-acct"
        user = "fallback-user"
        password = "fallback-pass"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("fallback-acct")
  })

  it("returns null when connections.toml exists but has no connection sections", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        default_connection_name = "foo"
      `,
    })

    expect(readTomlDefaultConnection()).toBeNull()
  })

  it("reads connections from connections.toml nested format [connections.name]", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [connections.prod]
        account = "nested-acct"
        user = "nested-user"
        password = "nested-pass"
      `,
    })

    process.env.SNOWFLAKE_CONNECTION_NAME = "prod"
    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("nested-acct")
  })

  it("nested [connections.*] format wins over legacy top-level on same name", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [test]
        account = "legacy-acct"
        user = "legacy-user"
        password = "legacy-pass"
        [connections.test]
        account = "nested-acct"
        user = "nested-user"
        password = "nested-pass"
      `,
    })

    process.env.SNOWFLAKE_CONNECTION_NAME = "test"
    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("nested-acct")
  })

  it("resolves legacy and nested connections coexisting in connections.toml", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [legacy_conn]
        account = "legacy-acct"
        user = "legacy-user"
        password = "legacy-pass"
        [connections.new_conn]
        account = "new-acct"
        user = "new-user"
        password = "new-pass"
      `,
    })

    process.env.SNOWFLAKE_CONNECTION_NAME = "new_conn"
    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("new-acct")
  })

  it("SNOWFLAKE_HOME changes the config file lookup directory", () => {
    process.env.SNOWFLAKE_HOME = "/custom-snowflake-dir"
    setupFiles({
      ["/custom-snowflake-dir/connections.toml"]: `
        [myconn]
        account = "custom-home-acct"
        user = "custom-home-user"
        password = "custom-home-pass"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("custom-home-acct")
  })

  it("caches the result across calls", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [cached]
        account = "cached-acct"
        user = "cached-user"
        password = "cached-pass"
      `,
    })

    const first = readTomlDefaultConnection()
    // Change the mock -- should NOT affect result due to caching
    vi.mocked(fs.existsSync).mockReturnValue(false)
    const second = readTomlDefaultConnection()

    expect(first).toEqual(second)
    expect(second!.account).toBe("cached-acct")
  })

  it("cache is cleared by resetTomlConfigCache", () => {
    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [v1]
        account = "v1-acct"
        user = "v1-user"
        password = "v1-pass"
      `,
    })

    const first = readTomlDefaultConnection()
    expect(first!.account).toBe("v1-acct")

    resetTomlConfigCache()

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [v2]
        account = "v2-acct"
        user = "v2-user"
        password = "v2-pass"
      `,
    })

    const second = readTomlDefaultConnection()
    expect(second!.account).toBe("v2-acct")
  })

  // --- Env var overlay tests (spec §3.B) ---

  it("SNOWFLAKE_ACCOUNT env var overlays on toml connection", () => {
    process.env.SNOWFLAKE_ACCOUNT = "env-override-acct"

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [myconn]
        account = "file-acct"
        user = "file-user"
        password = "file-pass"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("env-override-acct")
    expect(conn!.user).toBe("file-user") // non-overridden field preserved
  })

  it("multiple SNOWFLAKE_<KEY> env vars overlay on toml connection", () => {
    process.env.SNOWFLAKE_DATABASE = "env-db"
    process.env.SNOWFLAKE_SCHEMA = "env-schema"
    process.env.SNOWFLAKE_ROLE = "env-role"

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [myconn]
        account = "file-acct"
        user = "file-user"
        database = "file-db"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("file-acct") // not overridden
    expect(conn!.database).toBe("env-db")
    expect(conn!.schema).toBe("env-schema")
    expect(conn!.role).toBe("env-role")
  })

  it("env var overlay applies to all connections in cache", () => {
    process.env.SNOWFLAKE_WAREHOUSE = "env-warehouse"

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [conn1]
        account = "acct1"
        user = "user1"
        [conn2]
        account = "acct2"
        user = "user2"
      `,
    })

    // First call caches both connections with overlay applied
    process.env.SNOWFLAKE_CONNECTION_NAME = "conn1"
    const conn1 = readTomlDefaultConnection()
    expect(conn1!.warehouse).toBe("env-warehouse")

    // Switch to conn2 (still uses cache)
    process.env.SNOWFLAKE_CONNECTION_NAME = "conn2"
    resetTomlConfigCache()

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [conn1]
        account = "acct1"
        user = "user1"
        [conn2]
        account = "acct2"
        user = "user2"
      `,
    })

    const conn2 = readTomlDefaultConnection()
    expect(conn2!.warehouse).toBe("env-warehouse")
    expect(conn2!.account).toBe("acct2")
  })

  it("ignores non-connection SNOWFLAKE_* env vars", () => {
    process.env.SNOWFLAKE_CONNECTION_NAME = "myconn"
    process.env.SNOWFLAKE_RANDOM_KEY = "ignored"

    setupFiles({
      [path.join(HOME, ".snowflake", "connections.toml")]: `
        [myconn]
        account = "file-acct"
        user = "file-user"
      `,
    })

    const conn = readTomlDefaultConnection()
    expect(conn).not.toBeNull()
    expect(conn!.account).toBe("file-acct")
    expect((conn as Record<string, unknown>).random_key).toBeUndefined()
  })
})

// ---------------------------------------------------------------------------
// querySnowflake: retry on terminated connection
// ---------------------------------------------------------------------------

describe("querySnowflake: retry on terminated connection", () => {
  let querySnowflake: (query: string) => Promise<Record<string, unknown>[]>

  beforeEach(async () => {
    vi.resetModules()
    delete process.env.SNOWFLAKE_USER
    delete process.env.SNOWFLAKE_PASSWORD

    vi.doMock("fs", () => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const actual = require("fs") as typeof import("fs")
      return {
        default: {
          ...actual,
          existsSync: (p: string) => p === "/snowflake/session/token" || actual.existsSync(p),
          readFileSync: (p: string, ...args: unknown[]) => {
            if (p === "/snowflake/session/token") return "fake-spcs-token"
            return (actual.readFileSync as (...a: unknown[]) => unknown)(p, ...args)
          },
        },
        existsSync: (p: string) => p === "/snowflake/session/token" || actual.existsSync(p),
        readFileSync: (p: string, ...args: unknown[]) => {
          if (p === "/snowflake/session/token") return "fake-spcs-token"
          return (actual.readFileSync as (...a: unknown[]) => unknown)(p, ...args)
        },
      }
    })

    const mod = await import("@/lib/snowflake")
    querySnowflake = mod.querySnowflake
  })

  afterEach(() => {
    vi.doUnmock("fs")
  })

  it("retries once when execute fails with 'terminated connection' and succeeds on retry", async () => {
    let callCount = 0
    mockExecuteImpl = ({ complete }) => {
      callCount++
      if (callCount === 1) {
        complete(new Error("terminated connection"), null, null)
      } else {
        complete(null, { getQueryId: () => "qid-retry-ok" }, [{ result: 1 }])
      }
    }

    const rows = await querySnowflake("SELECT 1")
    expect(rows).toEqual([{ result: 1 }])
    expect(callCount).toBe(2)
  })

  it("does NOT retry on errors that do not include 'terminated connection'", async () => {
    let callCount = 0
    mockExecuteImpl = ({ complete }) => {
      callCount++
      complete(new Error("SQL compilation error: unexpected 'SELECX'"), null, null)
    }

    await expect(querySnowflake("SELECX 1")).rejects.toThrow()
    expect(callCount).toBe(1)
  })

  it("does NOT retry more than once — re-throws after a single retry also fails", async () => {
    let callCount = 0
    mockExecuteImpl = ({ complete }) => {
      callCount++
      complete(new Error("terminated connection"), null, null)
    }

    await expect(querySnowflake("SELECT 1")).rejects.toThrow()
    expect(callCount).toBe(2)
  })

  it("ownersPool is cleared before the retry — createPool is called twice", async () => {
    const { default: snowflakeSdk } = await import("snowflake-sdk")
    const createPool = vi.mocked(snowflakeSdk.createPool)
    createPool.mockClear()

    let callCount = 0
    mockExecuteImpl = ({ complete }) => {
      callCount++
      if (callCount === 1) {
        complete(new Error("terminated connection"), null, null)
      } else {
        complete(null, { getQueryId: () => "qid-fresh" }, [{ ok: true }])
      }
    }

    await querySnowflake("SELECT 1")
    expect(createPool.mock.calls.length).toBeGreaterThanOrEqual(2)
  })
})

// ---------------------------------------------------------------------------
// getSnowflakeBaseUrl
// ---------------------------------------------------------------------------

describe("getSnowflakeBaseUrl", () => {
  afterEach(() => {
    vi.doUnmock("fs")
    delete process.env.SNOWFLAKE_ACCOUNT_URL
    delete process.env.SNOWFLAKE_HOST
  })

  it("returns SNOWFLAKE_ACCOUNT_URL env var when set", async () => {
    process.env.SNOWFLAKE_ACCOUNT_URL = "https://myaccount.snowflakecomputing.com"
    vi.resetModules()
    vi.doMock("fs", makeNoTomlFsMock)
    const mod = await import("@/lib/snowflake")
    expect(mod.getSnowflakeBaseUrl()).toBe("https://myaccount.snowflakecomputing.com")
  })

  it("returns https://HOST when SNOWFLAKE_HOST is set", async () => {
    process.env.SNOWFLAKE_HOST = "myaccount.snowflakecomputing.com"
    vi.resetModules()
    vi.doMock("fs", makeNoTomlFsMock)
    const mod = await import("@/lib/snowflake")
    expect(mod.getSnowflakeBaseUrl()).toBe("https://myaccount.snowflakecomputing.com")
  })

  it("returns null when no env vars or toml config are available", async () => {
    vi.resetModules()
    vi.doMock("fs", makeNoTomlFsMock)
    const mod = await import("@/lib/snowflake")
    expect(mod.getSnowflakeBaseUrl()).toBeNull()
  })

  it("normalises account identifier to lowercase hyphenated URL", async () => {
    vi.resetModules()
    vi.doMock("fs", () => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const actual = require("fs") as typeof import("fs")
      const tomlContent = "[myconn]\naccount = \"SFCOGSOPS-SNOWHOUSE_AWS_US_WEST_2\""
      return {
        default: {
          ...actual,
          existsSync: (p: string) => p.endsWith("connections.toml"),
          readFileSync: (p: string, ...args: unknown[]) =>
            p.endsWith("connections.toml") ? tomlContent : (actual.readFileSync as (...a: unknown[]) => unknown)(p, ...args),
        },
        existsSync: (p: string) => p.endsWith("connections.toml"),
        readFileSync: (p: string, ...args: unknown[]) =>
          p.endsWith("connections.toml") ? tomlContent : (actual.readFileSync as (...a: unknown[]) => unknown)(p, ...args),
      }
    })
    const mod = await import("@/lib/snowflake")
    expect(mod.getSnowflakeBaseUrl()).toBe("https://sfcogsops-snowhouse-aws-us-west-2.snowflakecomputing.com")
  })
})

// ---------------------------------------------------------------------------
// getRestApiAuthHeader
// ---------------------------------------------------------------------------

describe("getRestApiAuthHeader", () => {
  beforeEach(() => {
    vi.resetModules()
    delete process.env.SNOWFLAKE_USER
    delete process.env.SNOWFLAKE_PASSWORD
  })

  afterEach(() => {
    vi.doUnmock("fs")
  })

  it("returns Bearer <token> when SPCS service token is present", async () => {
    vi.doMock("fs", () => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const actual = require("fs") as typeof import("fs")
      return {
        default: {
          ...actual,
          existsSync: (p: string) => p === "/snowflake/session/token",
          readFileSync: (p: string, ...args: unknown[]) =>
            p === "/snowflake/session/token" ? "spcs-token-abc" : (actual.readFileSync as (...a: unknown[]) => unknown)(p, ...args),
        },
        existsSync: (p: string) => p === "/snowflake/session/token",
        readFileSync: (p: string, ...args: unknown[]) =>
          p === "/snowflake/session/token" ? "spcs-token-abc" : (actual.readFileSync as (...a: unknown[]) => unknown)(p, ...args),
      }
    })
    const mod = await import("@/lib/snowflake")
    expect(mod.getRestApiAuthHeader()).toBe("Bearer spcs-token-abc")
  })

  it("returns Bearer <empty> (will 401) when no token or OAuth config is available", async () => {
    vi.doMock("fs", () => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const actual = require("fs") as typeof import("fs")
      return {
        default: { ...actual, existsSync: () => false },
        existsSync: () => false,
        readFileSync: actual.readFileSync,
      }
    })
    const mod = await import("@/lib/snowflake")
    expect(mod.getRestApiAuthHeader()).toBe("Bearer ")
  })
})
