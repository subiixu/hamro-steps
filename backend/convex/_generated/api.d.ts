/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as crons from "../crons.js";
import type * as days from "../days.js";
import type * as families from "../families.js";
import type * as home from "../home.js";
import type * as http from "../http.js";
import type * as lib_access from "../lib/access.js";
import type * as lib_activity from "../lib/activity.js";
import type * as lib_apple from "../lib/apple.js";
import type * as lib_cleanup from "../lib/cleanup.js";
import type * as lib_constants from "../lib/constants.js";
import type * as lib_errors from "../lib/errors.js";
import type * as lib_nepalDay from "../lib/nepalDay.js";
import type * as lib_tokens from "../lib/tokens.js";
import type * as lib_totals from "../lib/totals.js";
import type * as lib_validate from "../lib/validate.js";
import type * as sessions from "../sessions.js";
import type * as status from "../status.js";
import type * as steps from "../steps.js";
import type * as users from "../users.js";
import type * as walks from "../walks.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  crons: typeof crons;
  days: typeof days;
  families: typeof families;
  home: typeof home;
  http: typeof http;
  "lib/access": typeof lib_access;
  "lib/activity": typeof lib_activity;
  "lib/apple": typeof lib_apple;
  "lib/cleanup": typeof lib_cleanup;
  "lib/constants": typeof lib_constants;
  "lib/errors": typeof lib_errors;
  "lib/nepalDay": typeof lib_nepalDay;
  "lib/tokens": typeof lib_tokens;
  "lib/totals": typeof lib_totals;
  "lib/validate": typeof lib_validate;
  sessions: typeof sessions;
  status: typeof status;
  steps: typeof steps;
  users: typeof users;
  walks: typeof walks;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
