import {
  LiquidityDivestedEvent,
  LiquidityInvestedEvent,
  LiquidityLossPaidEvent,
  LiquidityYieldPulledEvent,
  StrategyEnabledEvent,
} from '../types/contracts/currency/ReinvestManagerBase';
import {
  ApplicationAppliedEvent,
  ApplicationApprovedEvent,
  ApplicationDeclinedEvent,
  ApplicationSubmittedEvent,
  ClaimAppliedEvent,
  ClaimApprovedEvent,
  ClaimSubmittedEvent,
} from '../types/contracts/governance/ApprovalCatalog';
import { ProxyCreatedEvent } from '../types/contracts/governance/ProxyCatalog';
import { TokenSwappedEvent } from '../types/contracts/premium/mocks/MockBalancerLib2';
import { TransferEvent } from '../types/contracts/tools/tokens/ERC20Base';

import { addNamedEvent, EventFactory, wrap } from './event-wrapper';

const stub = null as unknown;

export const Events = {
  TokenSwapped: wrap(stub as TokenSwappedEvent),
  ProxyCreated: wrap(stub as ProxyCreatedEvent),
  Transfer: wrap(stub as TransferEvent),
  ApplicationSubmitted: wrap(stub as ApplicationSubmittedEvent),
  ApplicationApproved: wrap(stub as ApplicationApprovedEvent),
  ApplicationApplied: wrap(stub as ApplicationAppliedEvent),
  ApplicationDeclined: wrap(stub as ApplicationDeclinedEvent),
  ClaimSubmitted: wrap(stub as ClaimSubmittedEvent),
  ClaimApproved: wrap(stub as ClaimApprovedEvent),
  ClaimApplied: wrap(stub as ClaimAppliedEvent),
  StrategyEnabled: wrap(stub as StrategyEnabledEvent),
  LiquidityInvested: wrap(stub as LiquidityInvestedEvent),
  LiquidityDivested: wrap(stub as LiquidityDivestedEvent),
  LiquidityYieldPulled: wrap(stub as LiquidityYieldPulledEvent),
  LiquidityLossPaid: wrap(stub as LiquidityLossPaidEvent),
};

Object.entries(Events).forEach(([name, factory]) => addNamedEvent(factory, name));

export const eventByName = (s: string): EventFactory => Events[s] as EventFactory;
