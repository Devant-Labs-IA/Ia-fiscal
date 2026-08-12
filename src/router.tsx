import { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";

import {
  FISCAL_QUERY_GC_TIME_MS,
  FISCAL_QUERY_STALE_TIME_MS,
  shouldRetryFiscalQuery,
} from "@/lib/query-policy";

import { routeTree } from "./routeTree.gen";

export const getRouter = () => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: FISCAL_QUERY_STALE_TIME_MS,
        gcTime: FISCAL_QUERY_GC_TIME_MS,
        retry: shouldRetryFiscalQuery,
        retryDelay: 750,
        refetchOnWindowFocus: false,
      },
      mutations: {
        retry: false,
      },
    },
  });

  const router = createRouter({
    routeTree,
    context: { queryClient },
    scrollRestoration: true,
    defaultPreloadStaleTime: FISCAL_QUERY_STALE_TIME_MS,
  });

  return router;
};