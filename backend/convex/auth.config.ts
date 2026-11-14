import { AuthConfig } from "convex/server";
import { JWT_AUDIENCE } from "./lib/constants";

/**
 * Our own RS256 access JWTs, issued by the HTTP actions in http.ts and
 * verified by Convex against the JWKS we serve. The issuer is this
 * deployment's site URL (CONVEX_SITE_URL is set by Convex itself).
 */
export default {
  providers: [
    {
      type: "customJwt",
      applicationID: JWT_AUDIENCE,
      issuer: process.env.CONVEX_SITE_URL!,
      jwks: `${process.env.CONVEX_SITE_URL}/.well-known/jwks.json`,
      algorithm: "RS256",
    },
  ],
} satisfies AuthConfig;
