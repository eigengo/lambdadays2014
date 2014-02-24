package org.eigengo.cm.api

import akka.actor.{ActorContext, Props, Actor, ActorRef}
import spray.http._
import spray.http.HttpResponse
import spray.can.Http
import spray.can.Http.RegisterChunkHandler
import org.eigengo.cm.core.CoordinatorActor
import spray.routing.{RequestContext, Directives}
import spray.httpx.marshalling.{MetaMarshallers, BasicToResponseMarshallers}
import scala.concurrent.ExecutionContext
import spray.routing

object RecogService {
  val Recog   = "recog"
  val MJPEG   = "mjpeg"
  val H264    = "h264"
}

trait BasicRecogService extends Directives {
  import scala.concurrent.duration._
  import akka.pattern.ask
  import CoordinatorActor._
  import RecogService._

  implicit val timeout = akka.util.Timeout(2.seconds)

  def normalRoute(coordinator: ActorRef)(implicit ec: ExecutionContext): routing.Route = ???
}

trait StreamingRecogService extends Directives {
  this: Actor =>

  import CoordinatorActor._
  import RecogService._

  def chunkedRoute(coordinator: ActorRef): routing.Route = {
    def handleChunksWith(creator: => Actor): RequestContext => Unit = {
      val handler = context.actorOf(Props(creator))
      sender ! RegisterChunkHandler(handler)

      {_ => ()}
    }

    ???
  }

}

class RecogServiceActor(coordinator: ActorRef) extends Actor with BasicRecogService with StreamingRecogService {
  import context.dispatcher
  val normal = normalRoute(coordinator)
  val chunked = chunkedRoute(coordinator)

  def receive: Receive = ???

}

class StreamingRecogServiceActor[A](coordinator: ActorRef, sessionId: String, message: (String, Array[Byte]) => A) extends Actor {

  def receive = {
    // stream mid to /recog/[h264|mjpeg]/:id; see above ^
    case MessageChunk(data, _) =>
      // our work is done: bang it to the coordinator.
      coordinator ! message(sessionId, data.toByteArray)

    // stream end to /recog/[h264|mjpeg]/:id; see above ^^
    case ChunkedMessageEnd(_, _) =>
      // we say nothing back
      sender ! HttpResponse(entity = "{}")
      context.stop(self)
  }

}

