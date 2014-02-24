package org.eigengo.cm.core

import akka.actor._
import scala.concurrent.{ ExecutionContext, Future }
import com.github.sstone.amqp.{ ConnectionOwner, RpcClient }
import akka.util.Timeout
import com.github.sstone.amqp.Amqp.Publish
import com.github.sstone.amqp.RpcClient.Response
import com.github.sstone.amqp.RpcClient.Request
import com.github.sstone.amqp.Amqp.Delivery
import spray.json.{ JsonParser, JsonReader, DefaultJsonProtocol }

private[core] object RecogSessionActor {

  // receive image to be processed
  private[core] case class Image(image: Array[Byte]) extends AnyVal
  // receive chunk of a frame to be processed
  private[core] case class Frame(frameChunk: Array[Byte]) extends AnyVal

  // FSM states
  private[core] sealed trait State
  private[core] case object Idle extends State
  private[core] case object Completed extends State
  private[core] case object Aborted extends State
  private[core] case object Active extends State

  // FSM data
  private[core] sealed trait Data
  private[core] case object Empty extends Data
  private[core] case class Starting(minCoins: Int) extends Data
  private[core] case class Running(decoder: DecoderContext) extends Data

  // CV responses
  private[core] case class Point(x: Int, y: Int)
  private[core] case class Coin(center: Point, radius: Double)
  private[core] case class CoinResponse(coins: List[Coin], succeeded: Boolean)

}

trait RecogSessionActorFormats extends DefaultJsonProtocol {
  import RecogSessionActor._

  implicit val PointFormat = jsonFormat2(Point)
  implicit val CoinFormat = jsonFormat2(Coin)
  implicit val CoinResponseFormat = jsonFormat2(CoinResponse)
}

/**
 * This actor deals with the states of the recognition session. We use FSM here--even though
 * we only have a handful of states, recognising things sometimes needs many more states
 * and using ``become`` and ``unbecome`` of the ``akka.actor.ActorDSL._`` would be cumbersome.
 *
 * @param amqpConnection the AMQP connection we will use to create individual 'channels'
 * @param outputActor the actor that will receive our output
 */
private[core] class RecogSessionActor(amqpConnection: ActorRef, outputActor: ActorRef) extends
  Actor with FSM[RecogSessionActor.State, RecogSessionActor.Data] with
  AmqpOperations with RecogSessionActorFormats with ImageEncoding {
  import RecogSessionActor._
  import CoordinatorActor._
  import scala.concurrent.duration._
  import context.dispatcher

  // default timeout for all states
  val stateTimeout = 60.seconds
  val emptyBehaviour: StateFunction = { case _ => stay() }
  val amqp = ConnectionOwner.createChildActor(amqpConnection, Props(new RpcClient()))

}

private[core] trait AmqpOperations {

  def amqpAsk[A](amqp: ActorRef)(exchange: String, routingKey: String, payload: Array[Byte])(implicit ctx: ExecutionContext, reader: JsonReader[A]): Future[A] = {
    import scala.concurrent.duration._
    import akka.pattern.ask

    implicit val timeout = Timeout(2.seconds)

    (amqp ? Request(Publish(exchange, routingKey, payload) :: Nil)).map {
      case Response(Delivery(_, _, _, body) :: _) =>
        val s = new String(body)
        reader.read(JsonParser(s))
    }
  }

}
