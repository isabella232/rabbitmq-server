%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Plugin.
%%
%%   The Initial Developer of the Original Code is VMware, Inc.
%%   Copyright (c) 2007-2010 VMware, Inc.  All rights reserved.
-module(rabbit_mgmt_wm_queue_get).

-export([init/1, resource_exists/2, post_is_create/2, is_authorized/2,
         allowed_methods/2, process_post/2]).

-include("rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

%%--------------------------------------------------------------------

init(_Config) -> {ok, #context{}}.

allowed_methods(ReqData, Context) ->
    {['POST'], ReqData, Context}.

resource_exists(ReqData, Context) ->
    {case rabbit_mgmt_wm_queue:queue(ReqData) of
         not_found -> false;
         _         -> true
     end, ReqData, Context}.

post_is_create(ReqData, Context) ->
    {false, ReqData, Context}.

process_post(ReqData, Context) ->
    VHost = rabbit_mgmt_util:vhost(ReqData),
    Q = rabbit_mgmt_util:id(queue, ReqData),
    rabbit_mgmt_util:with_amqp_request(
      VHost, ReqData, Context,
      fun (Ch) ->
              case amqp_channel:call(Ch, #'basic.get'{queue = Q,
                                                      no_ack = true}) of
                  {#'basic.get_ok'{redelivered   = Redelivered,
                                   exchange      = Exchange,
                                   routing_key   = RoutingKey,
                                   message_count = MessageCount},
                   #amqp_msg{props = Props, payload = Payload}} ->
                      PayloadPart =
                          try
                              xmerl_ucs:from_utf8(Payload),
                              [{payload,          Payload},
                               {payload_encoding, string}]
                          catch exit:{ucs, _} ->
                                  [{payload,          base64:encode(Payload)},
                                   {payload_encoding, base64}]
                          end,
                      Msg = [{redelivered,   Redelivered},
                             {exchange,      Exchange},
                             {routing_key,   RoutingKey},
                             {message_count, MessageCount},
                             {properties, rabbit_mgmt_format:basic_properties(
                                            Props)}] ++
                          PayloadPart,
                      post_respond(Msg, ReqData, Context);
                  #'basic.get_empty'{} ->
                      {{halt, 404}, ReqData, Context}
              end
      end).

post_respond(Response, ReqData, Context) ->
    {JSON, _, _} = rabbit_mgmt_util:reply(Response, ReqData, Context),
    {true, wrq:set_resp_header(
             "content-type", "application/json",
             wrq:append_to_response_body(JSON, ReqData)), Context}.

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized_vhost(ReqData, Context).

%%--------------------------------------------------------------------
