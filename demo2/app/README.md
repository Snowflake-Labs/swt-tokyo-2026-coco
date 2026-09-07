# Next.js Template for Snowflake Apps

Minimal Next.js app deployed as a Snowflake App. Queries Snowflake using the [Node.js SDK](https://docs.snowflake.com/en/developer-guide/node-js/nodejs-driver) and demonstrates server-side rendering, API routes, and caller's-rights token handling.

## Local Development

```bash
npm install
npm run dev
```

The app reads Snowflake credentials automatically from your default [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/connecting/specify-credentials) connection in `~/.snowflake/config.toml`. No extra configuration needed if you already have `snow` CLI set up.

To use a specific named connection, set `SNOWFLAKE_CONNECTION_NAME`:

```bash
SNOWFLAKE_CONNECTION_NAME=myconn npm run dev
```

Alternatively, skip the config file entirely and provide env vars directly:

```bash
SNOWFLAKE_ACCOUNT=myaccount \
SNOWFLAKE_ACCOUNT_URL=https://myaccount.snowflakecomputing.com \
SNOWFLAKE_USER=myuser \
SNOWFLAKE_PASSWORD=mypassword \
SNOWFLAKE_WAREHOUSE=my_wh \
npm run dev
```

## Deploy

Edit `snowflake.yml` (set the database and app name), then:

```bash
snow app deploy
```

## Key Concepts

- **`querySnowflake(sql)`** returns `Record<string, any>[]`. Import it in any server component or route handler.
- **`export const dynamic = "force-dynamic"`** is required on pages/routes that query Snowflake — prevents build-time rendering when the DB is unreachable.
- **Client components** cannot call `querySnowflake()` directly. Create an API route and `fetch()` it instead (see `components/time-card.tsx` + `api/time/route.ts`).
- **Caller's rights** — The `/api/query` route reads the `sf-context-current-user-token` header provided by SPCS, combines it with the service token via `buildCallerRightsToken()`, and runs a query as the calling user. This lets you compare service context vs caller context side-by-side.
- **Branding** — Edit `lib/constants.ts` to change the app title and logo path (shared by the header and page metadata). Edit the CSS variables in `app/globals.css` to change the primary brand color. Button colors and focus rings update automatically.
- **Dark mode** — Built in via a custom theme provider in `components/theme-provider.tsx`. Respects the OS `prefers-color-scheme` setting by default. A Sun/Moon toggle in the header lets users override it. Light/dark CSS variable overrides live in `app/globals.css`.
- **API fetching** — `@tanstack/react-query` is pre-installed. Client components that fetch API routes should use `useQuery` (see `components/time-card.tsx`, `components/query-card.tsx`). The `QueryProvider` in `components/query-provider.tsx` wraps the root layout.
- **UI components** — shadcn/ui is pre-configured (`components.json`). `Button`, `Card`, `Alert`, `Badge`, `Separator`, and `Table` are already installed in `components/ui/`. Run `npx shadcn@latest add <component>` only for components not yet present.
